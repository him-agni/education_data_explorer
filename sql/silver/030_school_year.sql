-- Silver: one row per school per year (directory attributes, decoded).
-- Cleaning: trim and zero-pad ncessch to 12 digits and leaid to 7, try_cast every number, decode categories
-- through the dim_* tables, keep the latest-ingested row per (ncessch, year). Rejected rows go to
-- silver.quarantine. Out of scope on purpose: test scores, budgets, staffing (so no teacher or finance columns).
-- Special values: a negative code stays visible through the decoded label ("Not applicable"); charter becomes a
-- boolean only for the real 0/1 codes; the Title I fields are NULL for 2022-2024 because Urban delivers no values.
-- Requires: sql/silver/005_quarantine.sql and 010_dimensions.sql.

CREATE OR REPLACE VIEW silver.v_school_year_checked AS
WITH typed AS (
  SELECT
    lpad(NULLIF(trim(b.ncessch), ''), 12, '0') AS ncessch,
    lpad(NULLIF(trim(b.leaid), ''), 7, '0') AS leaid,
    try_cast(b.year AS INT) AS year,
    try_cast(b.fips AS INT) AS state_fips,
    b.school_name,
    b.lea_name,
    try_cast(b.school_status AS INT) AS school_status_code,
    try_cast(b.school_level AS INT) AS school_level_code,
    try_cast(b.school_type AS INT) AS school_type_code,
    try_cast(b.urban_centric_locale AS INT) AS locale_code,
    try_cast(b.charter AS INT) AS charter_code,
    try_cast(b.virtual AS INT) AS virtual_code,
    try_cast(b.title_i_status AS INT) AS title_i_status_code,
    try_cast(b.lowest_grade_offered AS INT) AS lowest_grade_offered,
    try_cast(b.highest_grade_offered AS INT) AS highest_grade_offered,
    b.county_code,
    try_cast(b.enrollment AS INT) AS directory_enrollment_raw,
    b.ncessch AS ncessch_raw,
    b.leaid AS leaid_raw,
    b.year AS year_raw,
    b._source_file,
    b._ingested_at,
    to_json(struct(b.*)) AS row_json
  FROM bronze.ccd_directory AS b
),

flagged AS (
  SELECT
    *,
    CASE
      WHEN ncessch IS NULL OR year IS NULL THEN 'missing_key'
      WHEN year NOT BETWEEN 2000 AND 2100 THEN 'bad_year'
      WHEN NOT (ncessch RLIKE '^[0-9]{12}$') OR leaid IS NULL OR NOT (leaid RLIKE '^[0-9]{7}$') THEN 'bad_id_format'
      WHEN state_fips IS NULL
        OR substr(ncessch, 1, 2) <> lpad(CAST(state_fips AS STRING), 2, '0')
        OR substr(leaid, 1, 2) <> lpad(CAST(state_fips AS STRING), 2, '0') THEN 'state_mismatch'
    END AS reason
  FROM typed
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY ncessch, year
      ORDER BY (reason IS NOT NULL), _ingested_at DESC, _source_file DESC
    ) AS rn
  FROM flagged
)

SELECT
  *,
  COALESCE(reason, CASE WHEN rn > 1 THEN 'duplicate_loser' END) AS final_reason
FROM ranked;

CREATE OR REPLACE TABLE silver.school_year
COMMENT 'Cleaned CCD school directory. One row per school (ncessch) per year. Decoded categories. Title I fields are empty for 2022-2024.'
AS
SELECT
  c.ncessch,
  c.year,
  c.state_fips,
  st.label AS state_name,
  c.leaid,
  c.school_name,
  c.lea_name,
  c.school_status_code,
  ss.label AS school_status,
  c.school_level_code,
  sl.label AS school_level,
  c.school_type_code,
  sty.label AS school_type,
  c.locale_code,
  lo.label AS locale,
  c.charter_code,
  CASE c.charter_code WHEN 1 THEN true WHEN 0 THEN false END AS is_charter,
  c.virtual_code,
  vi.label AS virtual_status,
  c.title_i_status_code,
  ti.label AS title_i_status,
  c.lowest_grade_offered,
  c.highest_grade_offered,
  c.county_code,
  CASE WHEN c.directory_enrollment_raw >= 0 THEN c.directory_enrollment_raw END AS directory_enrollment,
  c._source_file,
  c._ingested_at
FROM silver.v_school_year_checked AS c
LEFT JOIN silver.dim_state AS st ON st.code = c.state_fips
LEFT JOIN silver.dim_school_status AS ss ON ss.code = c.school_status_code
LEFT JOIN silver.dim_school_level AS sl ON sl.code = c.school_level_code
LEFT JOIN silver.dim_school_type AS sty ON sty.code = c.school_type_code
LEFT JOIN silver.dim_locale AS lo ON lo.code = c.locale_code
LEFT JOIN silver.dim_virtual AS vi ON vi.code = c.virtual_code
LEFT JOIN silver.dim_title_i_status AS ti ON ti.code = c.title_i_status_code
WHERE c.final_reason IS NULL;

INSERT INTO silver.quarantine
SELECT
  'bronze.ccd_directory',
  _source_file,
  final_reason,
  ncessch_raw,
  leaid_raw,
  year_raw,
  NULL,
  NULL,
  row_json,
  current_timestamp()
FROM silver.v_school_year_checked
WHERE final_reason IS NOT NULL;
