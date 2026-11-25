-- Gold: one row per school division, grade and school year (individual grades only, no all-grades total).
-- Built from silver.enrollment, which never contains the grade 99 total row, so these rows can be summed freely.
-- Same division rule and latest-name rule as gold.division_year_enrollment.
-- Requires the silver layer.

CREATE OR REPLACE TABLE gold.division_year_grade
COMMENT 'One row per Virginia school division, grade and school year. Public school fall membership for one grade. Grades are pre-kindergarten, kindergarten and grades 1 to 12. Sum across grades equals the division total.'
AS
WITH divisions AS (
  SELECT leaid, year, state_fips
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

by_grade AS (
  SELECT
    e.leaid,
    e.year AS school_year,
    e.grade_code,
    e.grade,
    SUM(e.enrollment) AS enrollment,
    COUNT(e.enrollment) AS schools_with_grade
  FROM silver.enrollment AS e
  INNER JOIN divisions AS d ON d.leaid = e.leaid AND d.year = e.year
  GROUP BY e.leaid, e.year, e.grade_code, e.grade
)

SELECT
  g.leaid,
  l.division_name,
  g.school_year,
  concat(CAST(g.school_year AS STRING), '-', lpad(CAST((g.school_year + 1) % 100 AS STRING), 2, '0')) AS school_year_label,
  g.grade_code,
  g.grade,
  g.enrollment,
  g.schools_with_grade,
  p.enrollment AS prior_year_enrollment,
  g.enrollment - p.enrollment AS change_from_prior_year,
  ROUND(100.0 * (g.enrollment - p.enrollment) / NULLIF(p.enrollment, 0), 2) AS pct_change_from_prior_year
FROM by_grade AS g
INNER JOIN latest AS l ON l.leaid = g.leaid
LEFT JOIN by_grade AS p ON p.leaid = g.leaid AND p.grade_code = g.grade_code AND p.school_year = g.school_year - 1;
