-- Silver: enrollment by race, split in two tables so the all-races total can never be summed with the races.
--   silver.enrollment_race        one row per school, grade, race and year, race groups only (race_code <> 99)
--   silver.enrollment_race_total  one row per school, grade and year, the race 99 "Total" row
-- Same cleaning as silver.enrollment (IDs, try_cast, special values, latest-ingested row wins, quarantine).
-- Extra rule: when a school's race total is missing (null), Urban delivers 0 for every race group. Those zeros are
-- not real, so they become NULL with status "missing". Otherwise a division's demographic mix would count
-- schools that did not report as schools with no students.
-- Only the all-grades rows (grade 99) are pulled today; grade_code is kept so by-grade rows could be added later.
-- Requires: sql/silver/005_quarantine.sql and 010_dimensions.sql.

CREATE OR REPLACE VIEW silver.v_enrollment_race_checked AS
WITH typed AS (
  SELECT
    lpad(NULLIF(trim(b.ncessch), ''), 12, '0') AS ncessch,
    lpad(NULLIF(trim(b.leaid), ''), 7, '0') AS leaid,
    try_cast(b.year AS INT) AS year,
    try_cast(b.grade AS INT) AS grade_code,
    try_cast(b.race AS INT) AS race_code,
    try_cast(b.fips AS INT) AS state_fips,
    try_cast(b.enrollment AS INT) AS enrollment_value,
    b.enrollment AS enrollment_raw,
    b.sex AS sex_raw,
    b.ncessch AS ncessch_raw,
    b.leaid AS leaid_raw,
    b.year AS year_raw,
    b.grade AS grade_raw,
    b._source_file,
    b._ingested_at,
    to_json(struct(b.*)) AS row_json
  FROM bronze.ccd_enrollment_race AS b
),

flagged AS (
  SELECT
    t.*,
    g.label AS grade,
    r.label AS race,
    CASE
      WHEN t.ncessch IS NULL OR t.year IS NULL OR t.grade_code IS NULL OR t.race_code IS NULL THEN 'missing_key'
      WHEN t.year NOT BETWEEN 2000 AND 2100 THEN 'bad_year'
      WHEN NOT (t.ncessch RLIKE '^[0-9]{12}$') OR t.leaid IS NULL OR NOT (t.leaid RLIKE '^[0-9]{7}$') THEN 'bad_id_format'
      WHEN t.state_fips IS NULL
        OR substr(t.ncessch, 1, 2) <> lpad(CAST(t.state_fips AS STRING), 2, '0')
        OR substr(t.leaid, 1, 2) <> lpad(CAST(t.state_fips AS STRING), 2, '0') THEN 'state_mismatch'
      WHEN g.code IS NULL THEN 'unknown_grade'
      WHEN r.code IS NULL THEN 'unknown_race'
      WHEN NOT (t.sex_raw <=> '99') THEN 'unexpected_breakdown'
      WHEN t.enrollment_raw IS NOT NULL AND t.enrollment_value IS NULL THEN 'bad_enrollment_value'
      WHEN t.enrollment_value < -3 THEN 'unknown_special_value'
    END AS reason
  FROM typed AS t
  LEFT JOIN silver.dim_grade AS g ON g.code = t.grade_code
  LEFT JOIN silver.dim_race AS r ON r.code = t.race_code
),

ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY ncessch, year, grade_code, race_code
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

CREATE OR REPLACE TABLE silver.enrollment_race
COMMENT 'Cleaned CCD enrollment by race. One row per school, grade, race group and year. Race groups only: the all-races total is in silver.enrollment_race_total and must never be added to these rows. Zeros that stand in for a missing school total are set to NULL (status missing).'
AS
WITH good AS (
  SELECT * FROM silver.v_enrollment_race_checked WHERE final_reason IS NULL
),

marked AS (
  SELECT
    *,
    MAX(CASE WHEN race_code = 99 AND enrollment IS NULL THEN 1 ELSE 0 END)
      OVER (PARTITION BY ncessch, year, grade_code) AS total_is_missing
  FROM good
)

SELECT
  ncessch,
  year,
  grade_code,
  grade,
  race_code,
  race,
  state_fips,
  leaid,
  CASE WHEN total_is_missing = 1 AND enrollment = 0 THEN NULL ELSE enrollment END AS enrollment,
  CASE WHEN total_is_missing = 1 AND enrollment = 0 THEN 'missing' ELSE enrollment_status END AS enrollment_status,
  _source_file,
  _ingested_at
FROM marked
WHERE race_code <> 99;

CREATE OR REPLACE TABLE silver.enrollment_race_total
COMMENT 'Cleaned CCD enrollment by race, all-races total (race 99 "Total" row). One row per school, grade and year. Never add this to the race rows in silver.enrollment_race.'
AS
SELECT
  ncessch,
  year,
  grade_code,
  state_fips,
  leaid,
  enrollment AS total_enrollment,
  enrollment_status,
  _source_file,
  _ingested_at
FROM silver.v_enrollment_race_checked
WHERE final_reason IS NULL AND race_code = 99;

INSERT INTO silver.quarantine
SELECT
  'bronze.ccd_enrollment_race',
  _source_file,
  final_reason,
  ncessch_raw,
  leaid_raw,
  year_raw,
  grade_raw,
  enrollment_raw,
  row_json,
  current_timestamp()
FROM silver.v_enrollment_race_checked
WHERE final_reason IS NOT NULL;
