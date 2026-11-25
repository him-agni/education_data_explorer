-- Silver: enrollment, split in two tables so the all-grades total can never be summed with the grades.
--   silver.enrollment        one row per school, grade and year, individual grades only (grade_code <> 99)
--   silver.enrollment_total  one row per school and year, the grade 99 "Total" row
-- Cleaning: pad ncessch to 12 and leaid to 7, try_cast, special values to NULL plus enrollment_status, keep the
-- latest-ingested row per (ncessch, year, grade). Rejected rows go to silver.quarantine with a reason.
-- enrollment_status: reported (value >= 0) | missing (Urban delivered null, or code -1) | not_applicable (-2) |
-- suppressed (-3). Urban delivered null (no negative codes) for 2020-2022, so "missing" is the closest reading
-- of null; the codebook does not say whether those nulls mean missing or suppressed.
-- Requires: sql/silver/005_quarantine.sql and 010_dimensions.sql.

CREATE OR REPLACE VIEW silver.v_enrollment_checked AS
WITH typed AS (
  SELECT
    lpad(NULLIF(trim(b.ncessch), ''), 12, '0') AS ncessch,
    lpad(NULLIF(trim(b.leaid), ''), 7, '0') AS leaid,
    try_cast(b.year AS INT) AS year,
    try_cast(b.grade AS INT) AS grade_code,
    try_cast(b.fips AS INT) AS state_fips,
    try_cast(b.enrollment AS INT) AS enrollment_value,
    b.enrollment AS enrollment_raw,
    b.race AS race_raw,
    b.sex AS sex_raw,
    b.ncessch AS ncessch_raw,
    b.leaid AS leaid_raw,
    b.year AS year_raw,
    b.grade AS grade_raw,
    b._source_file,
    b._ingested_at,
    to_json(struct(b.*)) AS row_json
  FROM bronze.ccd_enrollment AS b
),

flagged AS (
  SELECT
    t.*,
    g.label AS grade,
    CASE
      WHEN t.ncessch IS NULL OR t.year IS NULL OR t.grade_code IS NULL THEN 'missing_key'
      WHEN t.year NOT BETWEEN 2000 AND 2100 THEN 'bad_year'
      WHEN NOT (t.ncessch RLIKE '^[0-9]{12}$') OR t.leaid IS NULL OR NOT (t.leaid RLIKE '^[0-9]{7}$') THEN 'bad_id_format'
      WHEN t.state_fips IS NULL
        OR substr(t.ncessch, 1, 2) <> lpad(CAST(t.state_fips AS STRING), 2, '0')
        OR substr(t.leaid, 1, 2) <> lpad(CAST(t.state_fips AS STRING), 2, '0') THEN 'state_mismatch'
      WHEN g.code IS NULL THEN 'unknown_grade'
      WHEN NOT (t.race_raw <=> '99') OR NOT (t.sex_raw <=> '99') THEN 'unexpected_breakdown'
      WHEN t.enrollment_raw IS NOT NULL AND t.enrollment_value IS NULL THEN 'bad_enrollment_value'
      WHEN t.enrollment_value < -3 THEN 'unknown_special_value'
    END AS reason
  FROM typed AS t
  LEFT JOIN silver.dim_grade AS g ON g.code = t.grade_code
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY ncessch, year, grade_code
      ORDER BY (reason IS NOT NULL), _ingested_at DESC, _source_file DESC
    ) AS rn
  FROM flagged
)

SELECT
  *,
  COALESCE(reason, CASE WHEN rn > 1 THEN 'duplicate_loser' END) AS final_reason,
  CASE WHEN enrollment_value >= 0 THEN enrollment_value END AS enrollment,
  CASE
    WHEN enrollment_raw IS NULL THEN 'missing'
    WHEN enrollment_value >= 0 THEN 'reported'
    WHEN enrollment_value = -1 THEN 'missing'
    WHEN enrollment_value = -2 THEN 'not_applicable'
    WHEN enrollment_value = -3 THEN 'suppressed'
  END AS enrollment_status
FROM ranked;

CREATE OR REPLACE TABLE silver.enrollment
COMMENT 'Cleaned CCD enrollment by grade. One row per school, grade and year, individual grades only. The all-grades total is in silver.enrollment_total and must never be added to these rows.'
AS
SELECT
  c.ncessch,
  c.year,
  c.grade_code,
  c.grade,
  c.state_fips,
  c.leaid,
  c.enrollment,
  c.enrollment_status,
  c._source_file,
  c._ingested_at
FROM silver.v_enrollment_checked AS c
WHERE c.final_reason IS NULL AND c.grade_code <> 99;

CREATE OR REPLACE TABLE silver.enrollment_total
COMMENT 'Cleaned CCD enrollment, all grades (grade 99 "Total" row). One row per school and year. Never add this to the grade rows in silver.enrollment.'
AS
SELECT
  c.ncessch,
  c.year,
  c.state_fips,
  c.leaid,
  c.enrollment AS total_enrollment,
  c.enrollment_status,
  c._source_file,
  c._ingested_at
FROM silver.v_enrollment_checked AS c
WHERE c.final_reason IS NULL AND c.grade_code = 99;

INSERT INTO silver.quarantine
SELECT
  'bronze.ccd_enrollment',
  _source_file,
  final_reason,
  ncessch_raw,
  leaid_raw,
  year_raw,
  grade_raw,
  enrollment_raw,
  row_json,
  current_timestamp()
FROM silver.v_enrollment_checked
WHERE final_reason IS NOT NULL;
