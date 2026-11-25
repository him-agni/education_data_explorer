-- Manual checks for the bronze and silver layers. Paste ONE statement at a time into the Databricks SQL Editor
-- (default catalog: workspace) and compare with the "Expected" lines above it.
-- These only read data. Nothing here changes a table.
-- Expected values were measured on 2026-11-25 against Virginia 2015-2024 data.

-- CHECK 1. Row counts in every layer.
-- Expected: bronze.ccd_directory 21485 | bronze.ccd_district_directory 2167 | bronze.ccd_enrollment 126066
--           silver.school_year 21485 | silver.district_year 2167 | silver.enrollment 106548
--           silver.enrollment_total 19518 | silver.quarantine 0
-- (silver.enrollment + silver.enrollment_total = 106548 + 19518 = 126066, the bronze enrollment count.)
SELECT 'bronze.ccd_directory' AS table_name, COUNT(*) AS row_count FROM bronze.ccd_directory
UNION ALL SELECT 'bronze.ccd_district_directory', COUNT(*) FROM bronze.ccd_district_directory
UNION ALL SELECT 'bronze.ccd_enrollment', COUNT(*) FROM bronze.ccd_enrollment
UNION ALL SELECT 'silver.school_year', COUNT(*) FROM silver.school_year
UNION ALL SELECT 'silver.district_year', COUNT(*) FROM silver.district_year
UNION ALL SELECT 'silver.enrollment', COUNT(*) FROM silver.enrollment
UNION ALL SELECT 'silver.enrollment_total', COUNT(*) FROM silver.enrollment_total
UNION ALL SELECT 'silver.quarantine', COUNT(*) FROM silver.quarantine;

-- CHECK 2. Statewide public school enrollment by year (the all-grades total rows).
-- Expected: 2015 1283548 | 2016 1286853 | 2017 1291462 | 2018 1289367 | 2019 1296941
--           2020 1251627 | 2021 1244624 | 2022 1260351 | 2023 1258852 | 2024 1257315
-- Outside check: Virginia Department of Education reports 1,262,262 for 2023-24 and 1,261,670 for 2024-25
-- (Urban years 2023 and 2024), about 0.3% higher.
SELECT year, SUM(total_enrollment) AS students
FROM silver.enrollment_total
GROUP BY year
ORDER BY year;

-- CHECK 3. The grade rows add up to the all-grades total, every year.
-- Expected: the difference column is 0 in all 10 years.
SELECT
  g.year,
  g.grades_sum,
  t.total_sum,
  g.grades_sum - t.total_sum AS difference
FROM (SELECT year, SUM(enrollment) AS grades_sum FROM silver.enrollment GROUP BY year) AS g
INNER JOIN (SELECT year, SUM(total_enrollment) AS total_sum FROM silver.enrollment_total GROUP BY year) AS t
  ON g.year = t.year
ORDER BY g.year;

-- CHECK 4. The five largest school divisions in 2024, with each division's latest name.
-- Expected: Fairfax County 179323 | Prince William County 90242 | Loudoun County 81486
--           Virginia Beach City 64731 | Chesterfield County 64194
SELECT d.lea_name AS division, SUM(t.total_enrollment) AS students
FROM silver.enrollment_total AS t
INNER JOIN silver.district_year AS d ON d.leaid = t.leaid AND d.year = t.year
WHERE t.year = 2024 AND d.is_school_division
GROUP BY d.lea_name
ORDER BY students DESC
LIMIT 5;

-- CHECK 5. How many school divisions report enrollment each year.
-- Expected: 132 for 2015 to 2021, then 131 for 2022 to 2024 (Covington City stops reporting, see CHECK 13).
SELECT t.year, COUNT(DISTINCT t.leaid) AS divisions_reporting
FROM silver.enrollment_total AS t
INNER JOIN silver.district_year AS d ON d.leaid = t.leaid AND d.year = t.year
WHERE d.is_school_division AND t.total_enrollment IS NOT NULL
GROUP BY t.year
ORDER BY t.year;

-- CHECK 6. Kindergarten students statewide by year (grade code 0).
-- Expected: 2015 90942 | 2016 90672 | 2017 91002 | 2018 91017 | 2019 92359
--           2020 80542 | 2021 86656 | 2022 86364 | 2023 85411 | 2024 84312
SELECT year, SUM(enrollment) AS kindergarten_students
FROM silver.enrollment
WHERE grade_code = 0
GROUP BY year
ORDER BY year;

-- CHECK 7. Missing enrollment is kept as a status, never turned into a zero.
-- Expected: 2020 missing 1 | 2021 missing 5 | 2022 missing 15
SELECT year, enrollment_status, COUNT(*) AS school_totals
FROM silver.enrollment_total
WHERE enrollment_status <> 'reported'
GROUP BY year, enrollment_status
ORDER BY year;

-- CHECK 8. Decoded words instead of codes (2024 schools by level).
-- Expected: Primary 1144 | Middle 340 | High 326 | Not applicable 247 | Missing/not reported 37
--           Prekindergarten 34 | Other 30 | Secondary 1
SELECT school_level, COUNT(*) AS schools
FROM silver.school_year
WHERE year = 2024
GROUP BY school_level
ORDER BY schools DESC;

-- CHECK 9. Charter schools by year (small numbers on purpose).
-- Expected: 8 charter schools in 2015 to 2020, 7 in 2021 to 2024 (out of 2128 to 2163 schools each year).
SELECT year, SUM(CASE WHEN is_charter THEN 1 ELSE 0 END) AS charter_schools, COUNT(*) AS all_schools
FROM silver.school_year
GROUP BY year
ORDER BY year;

-- CHECK 10. Title I data exists only through 2021 (schools with a Title I status per year).
-- Expected: 2113 to 2134 schools per year in 2015 to 2021, then 0 in 2022, 2023 and 2024.
SELECT year, COUNT(title_i_status) AS schools_with_title_i_status, COUNT(*) AS all_schools
FROM silver.school_year
GROUP BY year
ORDER BY year;

-- CHECK 11. Nothing was rejected (the real data is clean), and every row knows its source file.
-- Expected: 0 and 0.
SELECT
  (SELECT COUNT(*) FROM silver.quarantine) AS quarantined_rows,
  (SELECT COUNT(*) FROM silver.enrollment WHERE _source_file IS NULL) AS enrollment_rows_without_source;

-- CHECK 12. A school's record before and after cleaning (school 510003802280, grade 3, 2022: enrollment was null).
-- Expected: bronze row: grade 3, enrollment NULL | silver row: grade "Grade 3", enrollment NULL, status missing
SELECT 'bronze' AS layer, ncessch, year, grade, enrollment, CAST(NULL AS STRING) AS enrollment_status
FROM bronze.ccd_enrollment
WHERE ncessch = '510003802280' AND year = '2022' AND grade = '3'
UNION ALL
SELECT 'silver', ncessch, CAST(year AS STRING), grade, CAST(enrollment AS STRING), enrollment_status
FROM silver.enrollment
WHERE ncessch = '510003802280' AND year = 2022 AND grade_code = 3;

-- CHECK 13. KNOWN DATA ISSUE: Covington City merges into Alleghany (leaid 5100152) in 2022.
-- Expected: Alleghany 2021 = 1911 students, 2022 = 2878 (+50.6%). Covington's last year is 2021 with 963.
-- 1911 + 963 = 2874, close to 2878. Covington High and Jeter-Watson Elementary show status "Changed agency" in 2022.
SELECT t.year, d.leaid, MAX(d.lea_name) AS name_that_year, SUM(t.total_enrollment) AS students
FROM silver.enrollment_total AS t
INNER JOIN silver.district_year AS d ON d.leaid = t.leaid AND d.year = t.year
WHERE d.leaid IN ('5100152', '5100990')
GROUP BY t.year, d.leaid
ORDER BY d.leaid, t.year;

-- CHECK 14. KNOWN DATA ISSUE: single-year swings of 15% or more in a division's enrollment.
-- Expected: 11 rows, including Fredericksburg City 2022 (+93.0%) and 2021 (-45.0%), Giles County 2021 (+53.5%),
-- Radford City 2020 (+53.5%) and 2022 (+36.6%), Alleghany Highlands 2022 (+50.6%), King and Queen County 2024
-- (-28.5%) and Richmond City 2021 (-25.0%). Causes are not established; see docs/data_dictionary.md.
WITH yearly AS (
  SELECT t.leaid, t.year, SUM(t.total_enrollment) AS students
  FROM silver.enrollment_total AS t
  INNER JOIN silver.district_year AS d ON d.leaid = t.leaid AND d.year = t.year
  WHERE d.is_school_division
  GROUP BY t.leaid, t.year
),

with_prior AS (
  SELECT leaid, year, students, LAG(students) OVER (PARTITION BY leaid ORDER BY year) AS prior_students
  FROM yearly
)

SELECT
  (SELECT MAX_BY(lea_name, year) FROM silver.district_year AS n WHERE n.leaid = w.leaid) AS division,
  year,
  prior_students,
  students,
  ROUND(100.0 * (students - prior_students) / prior_students, 1) AS pct_change
FROM with_prior AS w
WHERE prior_students > 0 AND ABS(100.0 * (students - prior_students) / prior_students) >= 15
ORDER BY ABS(100.0 * (students - prior_students) / prior_students) DESC;
