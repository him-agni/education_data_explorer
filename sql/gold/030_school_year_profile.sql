-- Gold: one row per school per school year, with its decoded attributes and its enrollment.
-- All schools in the state directory are here, including closed and "future" ones: use school_status to filter.
-- division_name is the LATEST name of the school's agency. is_regular_school_division is false for regional,
-- specialized and state-operated agencies.
-- Title I fields are empty for 2022-2024 (Urban delivers no values); is_title_i_eligible is true for the codes
-- that say the school is eligible (targeted assistance or schoolwide) and false for "not eligible".
-- Requires the silver layer.

CREATE OR REPLACE TABLE gold.school_year_profile
COMMENT 'One row per Virginia public school per school year, with decoded attributes (level, type, locale, charter, Title I, status) and total fall membership. Title I is empty for 2022 to 2024.'
AS
WITH latest AS (
  SELECT
    leaid,
    MAX_BY(lea_name, year) AS division_name
  FROM silver.district_year
  GROUP BY leaid
)

SELECT
  s.ncessch,
  s.school_name,
  s.leaid,
  COALESCE(l.division_name, s.lea_name) AS division_name,
  COALESCE(d.is_school_division, false) AS is_regular_school_division,
  s.state_fips,
  s.state_name,
  s.year AS school_year,
  concat(CAST(s.year AS STRING), '-', lpad(CAST((s.year + 1) % 100 AS STRING), 2, '0')) AS school_year_label,
  s.school_status,
  s.school_level,
  s.school_type,
  s.locale,
  s.is_charter,
  s.virtual_status,
  s.title_i_status,
  CASE
    WHEN s.title_i_status_code BETWEEN 1 AND 5 THEN true
    WHEN s.title_i_status_code = 6 THEN false
  END AS is_title_i_eligible,
  lo.label AS lowest_grade_offered,
  hi.label AS highest_grade_offered,
  t.total_enrollment,
  t.enrollment_status
FROM silver.school_year AS s
LEFT JOIN latest AS l ON l.leaid = s.leaid
LEFT JOIN silver.district_year AS d ON d.leaid = s.leaid AND d.year = s.year
LEFT JOIN silver.enrollment_total AS t ON t.ncessch = s.ncessch AND t.year = s.year
LEFT JOIN silver.dim_grade AS lo ON lo.code = s.lowest_grade_offered
LEFT JOIN silver.dim_grade AS hi ON hi.code = s.highest_grade_offered;
