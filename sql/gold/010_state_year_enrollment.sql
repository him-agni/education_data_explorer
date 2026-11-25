-- Gold: one row per state per school year. Built from silver for Genie: plain names, no codes.
-- Counts every education agency in the state (regular divisions plus regional, specialized and state-operated
-- agencies), so the total matches the state's own published fall membership.
-- Requires the silver layer (sql/silver/*.sql). Comments and keys are added by 900_comments_and_keys.sql.

CREATE OR REPLACE TABLE gold.state_year_enrollment
COMMENT 'One row per state per school year. Public school fall membership across all grades (pre-kindergarten to grade 12 and ungraded), all education agencies in the state.'
AS
WITH totals AS (
  SELECT
    state_fips,
    year,
    SUM(total_enrollment) AS total_enrollment,
    COUNT(total_enrollment) AS schools_reporting
  FROM silver.enrollment_total
  GROUP BY state_fips, year
),

kindergarten AS (
  SELECT
    state_fips,
    year,
    SUM(enrollment) AS kindergarten_enrollment
  FROM silver.enrollment
  WHERE grade_code = 0
  GROUP BY state_fips, year
),

current_year AS (
  SELECT
    t.state_fips,
    st.label AS state_name,
    t.year AS school_year,
    t.total_enrollment,
    t.schools_reporting,
    k.kindergarten_enrollment
  FROM totals AS t
  LEFT JOIN kindergarten AS k ON k.state_fips = t.state_fips AND k.year = t.year
  LEFT JOIN silver.dim_state AS st ON st.code = t.state_fips
)

SELECT
  c.state_fips,
  c.state_name,
  c.school_year,
  concat(CAST(c.school_year AS STRING), '-', lpad(CAST((c.school_year + 1) % 100 AS STRING), 2, '0')) AS school_year_label,
  c.total_enrollment,
  c.schools_reporting,
  c.kindergarten_enrollment,
  p.total_enrollment AS prior_year_enrollment,
  c.total_enrollment - p.total_enrollment AS change_from_prior_year,
  ROUND(100.0 * (c.total_enrollment - p.total_enrollment) / NULLIF(p.total_enrollment, 0), 2) AS pct_change_from_prior_year
FROM current_year AS c
LEFT JOIN current_year AS p ON p.state_fips = c.state_fips AND p.school_year = c.school_year - 1;
