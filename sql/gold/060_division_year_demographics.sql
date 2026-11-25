-- Gold: one row per school division, race group and school year.
-- pct_of_division_enrollment is each group's share (0 to 100) of the students whose race was reported in that
-- division and year; schools with no reported total are left out of both the group and the denominator
-- (silver sets their placeholder zeros to NULL). Groups never include the all-races total row.
-- Race groups come from the codebook: White, Black, Hispanic, Asian, American Indian or Alaska Native,
-- Native Hawaiian or other Pacific Islander, Two or more races, Unknown. The "Unknown" group exists for only
-- some schools. Race detail is the all-grades count; it equals the division total in every year.
-- Same division rule and latest-name rule as gold.division_year_enrollment.
-- Requires the silver layer.

CREATE OR REPLACE TABLE gold.division_year_demographics
COMMENT 'One row per Virginia school division, race group and school year. Public school fall membership by race and ethnicity, all grades, with each group''s percent share of the division. Groups sum to the division total.'
AS
WITH divisions AS (
  SELECT leaid, year
  FROM silver.district_year
  WHERE is_school_division
),

latest AS (
  SELECT
    leaid,
    MAX_BY(lea_name, year) AS division_name
  FROM silver.district_year
  GROUP BY leaid
),

by_race AS (
  SELECT
    r.leaid,
    r.year AS school_year,
    r.race_code,
    r.race,
    SUM(r.enrollment) AS enrollment,
    COUNT(r.enrollment) AS schools_reporting
  FROM silver.enrollment_race AS r
  INNER JOIN divisions AS d ON d.leaid = r.leaid AND d.year = r.year
  WHERE r.grade_code = 99
  GROUP BY r.leaid, r.year, r.race_code, r.race
)

SELECT
  b.leaid,
  l.division_name,
  b.school_year,
  concat(CAST(b.school_year AS STRING), '-', lpad(CAST((b.school_year + 1) % 100 AS STRING), 2, '0')) AS school_year_label,
  b.race_code,
  b.race,
  b.enrollment,
  b.schools_reporting,
  ROUND(
    100.0 * b.enrollment / NULLIF(SUM(b.enrollment) OVER (PARTITION BY b.leaid, b.school_year), 0), 2
  ) AS pct_of_division_enrollment
FROM by_race AS b
INNER JOIN latest AS l ON l.leaid = b.leaid;
