-- Gold: one row per school ID, with when it opened and closed, from the directory's own status each year.
-- Why status and not "first and last year seen": a school's ID starts with its agency's ID, so a school that
-- changes agency gets a NEW ID (Covington High: 510099000367 until 2021, 510015200367 from 2022, status
-- "Changed agency"). Counting first and last appearance would record a false closing and a false opening.
-- Rules (status is the school's status at the start of the school year):
--   opened_school_year      first year the status is "New". NULL when the school was already open in 2015 or first
--                           appears with another status, so openings are never invented.
--   reopened_school_year    first year the status is "Reopened".
--   closed_school_year      the last year listed, only when the last status is "Closed" (a permanent closing).
--   had_temporary_closed_status  a "Closed" status in a year before the last year listed (the school came back).
--   changed_agency          the school has a "Changed agency" status: it moved, it did not open or close.
-- Requires the silver layer.

CREATE OR REPLACE TABLE gold.school_openings_closings
COMMENT 'One row per school ID. First and last school year listed in the directory, status at each end, and the year the school opened, reopened or closed, taken from the directory status. A school that changes agency gets a new ID, flagged by changed_agency.'
AS
WITH per_school AS (
  SELECT
    ncessch,
    MAX_BY(school_name, year) AS school_name,
    MAX_BY(leaid, year) AS leaid,
    MAX_BY(state_fips, year) AS state_fips,
    MIN(year) AS first_school_year_listed,
    MAX(year) AS last_school_year_listed,
    COUNT(*) AS years_listed,
    MIN_BY(school_status, year) AS first_status,
    MAX_BY(school_status, year) AS last_status,
    MIN(CASE WHEN school_status = 'New' THEN year END) AS opened_school_year,
    MIN(CASE WHEN school_status = 'Reopened' THEN year END) AS reopened_school_year,
    MAX(CASE WHEN school_status = 'Changed agency' THEN 1 ELSE 0 END) = 1 AS changed_agency,
    MAX(CASE WHEN school_status = 'Closed' THEN year END) AS latest_closed_status_year
  FROM silver.school_year
  GROUP BY ncessch
),

latest AS (
  SELECT
    leaid,
    MAX_BY(lea_name, year) AS division_name
  FROM silver.district_year
  GROUP BY leaid
)

SELECT
  p.ncessch,
  p.school_name,
  p.leaid,
  l.division_name,
  p.state_fips,
  st.label AS state_name,
  p.first_school_year_listed,
  p.last_school_year_listed,
  p.years_listed,
  p.first_status,
  p.last_status,
  p.opened_school_year,
  p.reopened_school_year,
  CASE WHEN p.last_status = 'Closed' THEN p.last_school_year_listed END AS closed_school_year,
  COALESCE(p.latest_closed_status_year < p.last_school_year_listed, false) AS had_temporary_closed_status,
  p.changed_agency,
  p.last_school_year_listed = (SELECT MAX(year) FROM silver.school_year)
    AND p.last_status IN ('Open', 'New', 'Reopened') AS is_open_in_latest_year
FROM per_school AS p
LEFT JOIN latest AS l ON l.leaid = p.leaid
LEFT JOIN silver.dim_state AS st ON st.code = p.state_fips;
