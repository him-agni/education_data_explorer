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

-- ===================== GOLD CHECKS (Phase 4) =====================

-- CHECK 15. Rows in each gold table.
-- Expected: state_year_enrollment 10 | division_year_enrollment 1317 | school_year_profile 21485
--           division_year_grade 18514 | school_openings_closings 2270 | division_year_demographics 10404
SELECT 'gold.state_year_enrollment' AS table_name, COUNT(*) AS row_count FROM gold.state_year_enrollment
UNION ALL SELECT 'gold.division_year_enrollment', COUNT(*) FROM gold.division_year_enrollment
UNION ALL SELECT 'gold.school_year_profile', COUNT(*) FROM gold.school_year_profile
UNION ALL SELECT 'gold.division_year_grade', COUNT(*) FROM gold.division_year_grade
UNION ALL SELECT 'gold.school_openings_closings', COUNT(*) FROM gold.school_openings_closings
UNION ALL SELECT 'gold.division_year_demographics', COUNT(*) FROM gold.division_year_demographics;

-- CHECK 16. Fairfax County growth columns, ready-made (Genie never has to invent the formula).
-- Expected: 2019-20 188887 | 2020-21 180028 (change -8859, -4.69 percent) | 2024-25 179323 (change -1391, -0.77 percent)
SELECT school_year_label, total_enrollment, change_from_prior_year, pct_change_from_prior_year
FROM gold.division_year_enrollment
WHERE division_name = 'Fairfax County Public Schools' AND school_year IN (2019, 2020, 2024)
ORDER BY school_year;

-- CHECK 17. Fairfax County race mix in 2024; the shares add up to 100.
-- Expected: White 64095 (35.74) | Black 17464 (9.74) | Hispanic 52413 (29.23) | Asian 33136 (18.48)
--           American Indian or Alaska Native 523 (0.29) | Native Hawaiian or other Pacific Islander 195 (0.11)
--           Two or more races 11497 (6.41) | Unknown 0 (0.00). The shares total 100.00.
SELECT race, enrollment, pct_of_division_enrollment
FROM gold.division_year_demographics
WHERE division_name = 'Fairfax County Public Schools' AND school_year = 2024
ORDER BY race_code;

-- CHECK 18. Kindergarten in Fairfax County from the grade table.
-- Expected: 2019 13070 | 2024 11393
SELECT school_year, enrollment AS kindergarten_students
FROM gold.division_year_grade
WHERE division_name = 'Fairfax County Public Schools' AND grade = 'Kindergarten' AND school_year IN (2019, 2024)
ORDER BY school_year;

-- CHECK 19. Schools opened and closed per year, from the directory status.
-- Expected (year: opened / closed): 2015: 12/13 | 2016: 10/8 | 2017: 14/27 | 2018: 11/16 | 2019: 13/5
--           2020: 7/5 | 2021: 8/2 | 2022: 13/9 | 2023: 13/16 | 2024: 16/20  (totals: 117 opened, 121 closed)
SELECT school_year, SUM(opened) AS schools_opened, SUM(closed) AS schools_closed
FROM (
  SELECT opened_school_year AS school_year, 1 AS opened, 0 AS closed
  FROM gold.school_openings_closings WHERE opened_school_year IS NOT NULL
  UNION ALL
  SELECT closed_school_year, 0, 1
  FROM gold.school_openings_closings WHERE closed_school_year IS NOT NULL
)
GROUP BY school_year
ORDER BY school_year;

-- CHECK 20. A school that moved to another division is NOT counted as a closing and an opening.
-- Expected: 510099000367: listed 2015 to 2021, last status Open, closed year empty, changed_agency false
--           510015200367: listed 2022 to 2023, first status "Changed agency", last status Closed, closed year 2023
--                         (a real closing in 2023), opened year empty, changed_agency true
SELECT ncessch, first_school_year_listed, last_school_year_listed, first_status, last_status,
  opened_school_year, closed_school_year, changed_agency
FROM gold.school_openings_closings
WHERE school_name LIKE 'Covington High%' OR school_name LIKE 'COVINGTON HIGH%'
ORDER BY first_school_year_listed;

-- CHECK 21. Title I schools by locale in 2021 (the last year Title I data exists).
-- Expected top rows: Suburb, large 168 | Rural, distant 156 | City, midsize 132 | Rural, fringe 99
-- For 2022 to 2024 the Title I columns are empty, so the same query returns no rows.
SELECT locale, COUNT(*) AS title_i_schools
FROM gold.school_year_profile
WHERE school_year = 2021 AND is_title_i_eligible AND school_status IN ('Open', 'New', 'Reopened')
GROUP BY locale
ORDER BY title_i_schools DESC;

-- CHECK 22. Charter schools in the latest year: a tiny sector.
-- Expected: 7 schools, 1270 students, 0.101 percent of state enrollment.
SELECT COUNT(*) AS charter_schools, SUM(total_enrollment) AS charter_students,
  ROUND(100.0 * SUM(total_enrollment) / (
    SELECT total_enrollment FROM gold.state_year_enrollment WHERE school_year = 2024
  ), 3) AS pct_of_state_enrollment
FROM gold.school_year_profile
WHERE school_year = 2024 AND is_charter AND school_status IN ('Open', 'New', 'Reopened');
