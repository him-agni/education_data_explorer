-- Silver: one row per school district or other education agency (leaid) per year.
-- Cleaning: trim and zero-pad leaid to 7 digits, try_cast every number (a bad value becomes NULL, never a
-- crash), decode categories through the dim_* tables, keep the latest-ingested row per (leaid, year).
-- Rejected rows go to silver.quarantine with a reason.
-- is_school_division = the agency is "Regular local school district" (agency_type 1) in ANY year. Checking year
-- by year would wrongly drop Greensville County and Williamsburg-James City County in 2015-2016, when Urban
-- labelled them "Supervisory union" (agency_type 3).
-- Requires: sql/silver/005_quarantine.sql and 010_dimensions.sql.

CREATE OR REPLACE VIEW silver.v_district_year_checked AS
WITH typed AS (
  SELECT
    lpad(NULLIF(trim(b.leaid), ''), 7, '0') AS leaid,
    try_cast(b.year AS INT) AS year,
    try_cast(b.fips AS INT) AS state_fips,
    b.lea_name,
    b.county_name,
    try_cast(b.agency_type AS INT) AS agency_type_code,
    try_cast(b.number_of_schools AS INT) AS number_of_schools,
    try_cast(b.urban_centric_locale AS INT) AS locale_code,
    try_cast(b.lowest_grade_offered AS INT) AS lowest_grade_offered,
    try_cast(b.highest_grade_offered AS INT) AS highest_grade_offered,
    b.leaid AS leaid_raw,
    b.year AS year_raw,
    b._source_file,
    b._ingested_at,
    to_json(struct(b.*)) AS row_json
  FROM bronze.ccd_district_directory AS b
),

flagged AS (
  SELECT
    *,
    CASE
      WHEN leaid IS NULL OR year IS NULL THEN 'missing_key'
      WHEN year NOT BETWEEN 2000 AND 2100 THEN 'bad_year'
      WHEN NOT (leaid RLIKE '^[0-9]{7}$') THEN 'bad_id_format'
      WHEN state_fips IS NULL OR substr(leaid, 1, 2) <> lpad(CAST(state_fips AS STRING), 2, '0') THEN 'state_mismatch'
    END AS reason
  FROM typed
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY leaid, year
      ORDER BY (reason IS NOT NULL), _ingested_at DESC, _source_file DESC
    ) AS rn
  FROM flagged
)

SELECT
  *,
  COALESCE(reason, CASE WHEN rn > 1 THEN 'duplicate_loser' END) AS final_reason
FROM ranked;

CREATE OR REPLACE TABLE silver.district_year
COMMENT 'Cleaned CCD school-district (agency) directory. One row per agency (leaid) per year. Decoded categories. is_school_division is true for agencies that are regular local school districts in any year.'
AS
SELECT
  c.leaid,
  c.year,
  c.state_fips,
  st.label AS state_name,
  c.lea_name,
  c.county_name,
  c.agency_type_code,
  at.label AS agency_type,
  MAX(CASE WHEN c.agency_type_code = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY c.leaid) = 1 AS is_school_division,
  c.number_of_schools,
  c.locale_code,
  lo.label AS locale,
  c.lowest_grade_offered,
  c.highest_grade_offered,
  c._source_file,
  c._ingested_at
FROM silver.v_district_year_checked AS c
LEFT JOIN silver.dim_state AS st ON st.code = c.state_fips
LEFT JOIN silver.dim_agency_type AS at ON at.code = c.agency_type_code
LEFT JOIN silver.dim_locale AS lo ON lo.code = c.locale_code
WHERE c.final_reason IS NULL;

INSERT INTO silver.quarantine
SELECT
  'bronze.ccd_district_directory',
  _source_file,
  final_reason,
  NULL,
  leaid_raw,
  year_raw,
  NULL,
  NULL,
  row_json,
  current_timestamp()
FROM silver.v_district_year_checked
WHERE final_reason IS NOT NULL;
