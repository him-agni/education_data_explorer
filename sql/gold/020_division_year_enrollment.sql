-- Gold: one row per school division per school year.
-- A "division" is a regular local school district (silver.district_year.is_school_division). Regional,
-- specialized and state-operated agencies are left out here but stay in gold.state_year_enrollment.
-- The division name is the LATEST name for that agency, so one division has one name in every year
-- (names change style across years: ACCOMACK CO PBLC SCHS became Accomack County Public Schools).
-- Year-over-year change is computed against the previous calendar year, so a gap year gives NULL, never a wrong
-- comparison. large_swing_flag marks one-year changes of 15% or more: those can come from a merger or a
-- reporting change (for example Covington City into Alleghany Highlands in 2022), not only real growth or decline.
-- Requires the silver layer.

CREATE OR REPLACE TABLE gold.division_year_enrollment
COMMENT 'One row per Virginia school division per school year. Public school fall membership, all grades. Divisions only (regular local school districts). Percent and headcount change from the prior year are columns.'
AS
WITH divisions AS (
  SELECT leaid, year, state_fips
  FROM silver.district_year
  WHERE is_school_division
),

latest AS (
  SELECT
    leaid,
    MAX_BY(lea_name, year) AS division_name,
    MAX_BY(county_name, year) AS county_name
  FROM silver.district_year
  GROUP BY leaid
),

totals AS (
  SELECT
    t.leaid,
    t.year,
    SUM(t.total_enrollment) AS total_enrollment,
    COUNT(t.total_enrollment) AS schools_reporting,
    SUM(CASE WHEN t.total_enrollment IS NULL THEN 1 ELSE 0 END) AS schools_missing_enrollment
  FROM silver.enrollment_total AS t
  INNER JOIN divisions AS d ON d.leaid = t.leaid AND d.year = t.year
  GROUP BY t.leaid, t.year
),

current_year AS (
  SELECT
    d.leaid,
    d.state_fips,
    st.label AS state_name,
    l.division_name,
    CASE
      WHEN l.division_name LIKE '% County Public Schools' THEN 'County'
      WHEN l.division_name LIKE '% City Public Schools' THEN 'City'
      WHEN l.division_name LIKE '% Town Public Schools' THEN 'Town'
      ELSE 'Other'
    END AS division_type,
    l.county_name,
    d.year AS school_year,
    t.total_enrollment,
    t.schools_reporting,
    t.schools_missing_enrollment
  FROM divisions AS d
  INNER JOIN totals AS t ON t.leaid = d.leaid AND t.year = d.year
  INNER JOIN latest AS l ON l.leaid = d.leaid
  LEFT JOIN silver.dim_state AS st ON st.code = d.state_fips
)

SELECT
  c.leaid,
  c.division_name,
  c.division_type,
  c.county_name,
  c.state_fips,
  c.state_name,
  c.school_year,
  concat(CAST(c.school_year AS STRING), '-', lpad(CAST((c.school_year + 1) % 100 AS STRING), 2, '0')) AS school_year_label,
  c.total_enrollment,
  c.schools_reporting,
  c.schools_missing_enrollment,
  p.total_enrollment AS prior_year_enrollment,
  c.total_enrollment - p.total_enrollment AS change_from_prior_year,
  ROUND(100.0 * (c.total_enrollment - p.total_enrollment) / NULLIF(p.total_enrollment, 0), 2) AS pct_change_from_prior_year,
  COALESCE(ABS(100.0 * (c.total_enrollment - p.total_enrollment) / NULLIF(p.total_enrollment, 0)) >= 15, false) AS large_swing_flag
FROM current_year AS c
LEFT JOIN current_year AS p ON p.leaid = c.leaid AND p.school_year = c.school_year - 1;
