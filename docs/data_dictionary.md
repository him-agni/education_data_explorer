# Data dictionary

Source: Urban Institute Education Data Portal API (`https://educationdata.urban.org/api/v1`), CCD data. Everything under "Verified" below comes from Urban's own metadata (`docs/codebook/api-variables.json`, `api-endpoints.json`) or from live API calls made on 2026-11-23. Cleaning rules are added here as each silver step is built, each with a before-and-after example.

## Endpoints used

| Dataset | Path | One row is | Years listed by Urban |
|---|---|---|---|
| School directory | `/schools/ccd/directory/{year}/` | a school in a year | 1986-2024 |
| Enrollment by grade | `/schools/ccd/enrollment/{year}/grade-{n}/` | a school and grade in a year | 1986-2024 |
| Enrollment by grade and race | `/schools/ccd/enrollment/{year}/grade-{n}/race/` | a school, grade and race in a year | 1986-2024 |
| District directory (not in v1) | `/school-districts/ccd/directory/{year}/` | a district in a year | 1986-2024 |

State filter: `?fips=51` (Virginia). Each response holds up to 10,000 records, with a `next` link.

## Year

`year` is the "Academic year (fall semester)": the year the academic year begins, so 2013 means 2013-14 (Urban's variable description). Genie instructions must say this. Virginia data exists for 2015-2024 (2025: directory returns 0 rows, enrollment returns HTTP 500).

## Missing-value codes (from the codebook, applies to the variables checked)

| Code | Meaning | Silver status |
|---|---|---|
| -1 | Missing/not reported | `missing` |
| -2 | Not applicable | `not_applicable` |
| -3 | Suppressed data | `suppressed` |

Observed in the live API for Virginia 2015-2024, grade 99: no negative enrollment codes. The API returned JSON `null` enrollment instead (1 row in 2020, 5 in 2021, 15 in 2022). Silver must treat `null` as its own case and record it as `missing`, unless the codebook or Urban says otherwise. To confirm before cleaning.

## Grade codes (`grade`)

-1 Pre-K | 0 Kindergarten | 1-13 grades 1-13 | 14 Adult education | 15 Ungraded | **99 Total (all grades)** | 999 Not specified.

The 99 row must never be summed with the individual grades.

URL spelling (tested against the live API, Virginia 2022): Pre-K is `grade-pk` (rows carry `grade = -1`; `grade--1` returns HTTP 500). Kindergarten is `grade-0` (also `grade-k`, identical). Grades 1-12 return rows. Grades 13, 14, 15 and 999 returned 0 rows for Virginia 2022, but the pull script still requests them for every year.

Row counts per grade code, Virginia 2022: -1: 1,087 | 0: 1,138 | 1: 1,139 | 2: 1,140 | 3: 1,141 | 4: 1,140 | 5: 1,125 | 6: 542 | 7: 423 | 8: 408 | 9: 353 | 10: 353 | 11: 352 | 12: 352 | 99: 1,884. Total 12,577 rows.

Reconciliation (Virginia 2022): the sum of non-null enrollment over the individual grade rows is 1,260,351, exactly equal to the sum over the grade-99 rows (1,260,351). 211 grade-level rows have `null` enrollment.

## Race codes (`race`)

1 White | 2 Black | 3 Hispanic | 4 Asian | 5 American Indian or Alaska Native | 6 Native Hawaiian or other Pacific Islander | 7 Two or more races | 8 Nonresident alien | 9 Unknown | 20 Other | **99 Total** | -1/-2/-3 as above. Urban notes that CCD used five categories through 2007 and seven since 2008.

## Sex (`sex`)

1 Male | 2 Female | 3 Gender not identified | 9 Unknown | 99 Total. The by-grade endpoint returns `race = 99` and `sex = 99` on every row.

## IDs

- `ncessch`: string, 12 characters (checked on all 2,159 Virginia schools in 2024). `ncessch_num` is the same ID as an integer.
- `leaid`: string, 7 characters. The first 2 digits are the state FIPS.
- Virginia's FIPS code is 51, so Virginia IDs start with 5 and cannot lose a leading zero. Padding matters only for states with FIPS below 10 (multi-state design), so it stays as a tested safety function.

## Directory fields available (Virginia, 2024 response)

`school_name`, `lea_name`, `leaid`, `ncessch`, `school_status`, `school_level`, `school_type`, `charter`, `virtual`, `urban_centric_locale`, `county_code`, `lowest_grade_offered`, `highest_grade_offered`, `title_i_status`, `title_i_eligible`, `title_i_schoolwide`, `magnet`, `enrollment`, `free_lunch`, `teachers_fte`, plus addresses and coordinates. Category code tables (`school_status`, `school_level`, `urban_centric_locale`, and so on) are in `api-variables.json` and are to be loaded into silver dimension tables.

## Coverage facts found in live data (Virginia, 2026-11-23)

| Fact | Detail |
|---|---|
| Title I | `title_i_status`, `title_i_eligible` populated 2015-2021 only. All empty 2022-2024. `title_i_schoolwide` follows the same pattern. `magnet` is empty in 2024. |
| Enrollment rows | Schools with a grade-99 row: about 1,860-1,880 in 2015-2017 and 2022-2024, about 2,112-2,121 in 2018-2020, 1,948 in 2021. Directory has 2,128-2,163 schools per year. |
| Total enrollment (grade 99, sum of non-null) | 2015: 1,283,548 | 2016: 1,286,853 | 2017: 1,291,462 | 2018: 1,289,367 | 2019: 1,296,941 | 2020: 1,251,627 | 2021: 1,244,624 | 2022: 1,260,351 | 2023: 1,258,852 | 2024: 1,257,315. Not yet compared with VDOE. |
| Divisions | 209 distinct `leaid` in the 2024 directory, of which 131 are regular school divisions. Resolved with the district directory, see "Divisions" below. |
| Enrollment vs directory | Every school with an enrollment row is in that year's directory. Directory schools without enrollment: 299 in 2024. |

## Cleaning rules (silver)

Built by `sql/silver/*.sql`. Every rejected row goes to `silver.quarantine` with a reason; nothing is dropped silently. The examples are real rows unless marked as a test case.

| # | Rule | Before (bronze, as delivered) | After (silver) |
|---|---|---|---|
| 1 | Trim and left-pad IDs to 12 (school) and 7 (district) digits; a blank becomes missing | Test case: `ncessch = '10000000001'` with `fips = '1'` | `ncessch = '010000000001'` |
| 2 | `try_cast` every number: a bad value becomes NULL and is caught by a rule, never a crash | `year = '2022'` (string) | `year = 2022` (INT) |
| 3 | Special values: a null or a negative code becomes NULL plus `enrollment_status` (`reported`, `missing`, `not_applicable`, `suppressed`) | School `510003802280`, grade 3, 2022: `enrollment = null` | `enrollment = NULL`, `enrollment_status = 'missing'` |
| 4 | The grade 99 "Total" row goes to its own table (`silver.enrollment_total`) and is never in `silver.enrollment` | `grade = '99'` row | Row in `enrollment_total`; 0 rows with `grade_code = 99` in `enrollment` |
| 5 | One row per key: the latest `_ingested_at` wins (ties: the later `_source_file`). Losers are quarantined as `duplicate_loser` | Test case: two rows for one school, year and grade | Newest row kept |
| 6 | State check (state-ready): the first two digits of the school and district IDs must equal `fips`, otherwise `state_mismatch` | Test case: `ncessch = '240000000001'`, `fips = '51'` | Quarantined |
| 7 | Decode categories through lookup tables built from the codebook (`dim_*`) | School `510009000030`, 2019: `school_level = '3'`, `school_status = '1'`, `urban_centric_locale = '13'`, `charter = '1'`, `title_i_status = '6'` | `High`, `Open`, `City, small`, `is_charter = true`, `School is not eligible for either Title I Targeted Assistance or Schoolwide program` |
| 8 | `is_school_division` is true when the agency is a "Regular local school district" (`agency_type` 1) in any year | Greensville County (`5101740`): type 3 in 2015-2016, type 1 after | `true` in all years |
| 9 | Quarantine rows with a missing key (`missing_key`), an impossible year (`bad_year`, outside 2000-2100), a malformed ID (`bad_id_format`), an unknown grade (`unknown_grade`), a race or sex other than the total (`unexpected_breakdown`), a non-numeric enrollment (`bad_enrollment_value`) or a value below -3 (`unknown_special_value`) | Test cases only: the real data triggers none of these | `silver.quarantine`, with the whole row as JSON |

Notes:
- Urban delivers `null`, not -1/-2/-3, for missing enrollment in 2020-2022. Silver reads null as `missing`. The codebook does not say whether those nulls mean missing or suppressed.
- Categorical codes below zero keep their meaning through the decoded label (for example `Not applicable`), so no information is lost.
- Title I is NULL for 2022-2024 because Urban delivers no values.
- Left out on purpose: test scores, budgets and staffing. No teacher or finance columns are kept.

## Divisions (resolved 2026-11-25)

Virginia's 2024 directory lists 209 agencies, but only 131 are regular school divisions (`agency_type` 1). The rest are regional, specialized or state-operated programs (technical centers, Governor's Schools, hospitals, state-operated programs). Agency names change style across years (`ACCOMACK CO PBLC SCHS` became `Accomack County Public Schools`), so display the latest name and join on `leaid`. The district directory (`bronze.ccd_district_directory`) supplies `agency_type`. 132 agencies are regular school divisions in at least one year. Students counted outside those 132 agencies: 97 to 315 per year (0.005% to 0.024%).

## Outside check against VDOE fall membership (2026-11-25)

Source: Virginia School Quality Profiles, "Commonwealth of Virginia: At-A-Glance" (https://schoolquality.virginia.gov/virginia-state-quality-profile/commonwealth-virginia-at-a-glance). The page says VDOE counts students enrolled in public schools on September 30. Urban `year` 2023 means the 2023-24 school year (fall 2023), so it lines up with VDOE's 2023-24 count.

| Urban year | Urban grade-99 total | VDOE "All Students" | Difference |
|---|---|---|---|
| 2023 | 1,258,852 | 1,262,262 (confirmed on the page) | -3,410 (-0.27%) |
| 2024 | 1,257,315 | 1,261,670 (confirmed on the page) | -4,355 (-0.35%) |
| 2022 | 1,260,351 | 1,263,605 (from a search summary, not confirmed on the page) | -3,254 (-0.26%) |

The gap is small and consistent. The cause of the gap is not known. Years 2015-2021 are not checked: the VDOE page lists no earlier years.

## Known data issues (found 2026-11-25, before building gold)

These come from Urban's source data, not from silver cleaning. They change how division-level trends should be read and must reach the Genie instructions.

1. **A division merger.** Covington City Public Schools (`5100990`) has enrollment through 2021 (963 students) and none after. In 2022 its schools Covington High and Jeter-Watson Elementary appear under Alleghany's ID (`5100152`) with status "Changed agency", and Alleghany is renamed Alleghany Highlands Public Schools. Alleghany jumps from 1,911 to 2,878 students (+50.6%); 1,911 + 963 = 2,874. This is consistent with a merger. Divisions reporting enrollment fall from 132 (2015-2021) to 131 (2022-2024).
2. **Unexplained single-year swings.** 11 division-years change by 15% or more in one year (see `sql/ops/manual_checks.sql`, check 14). Examples: Fredericksburg City -45.0% in 2021 and +93.0% in 2022 with the same 5 schools reporting, Radford City +53.5% in 2020 with the same 4 schools, Giles County +53.5% in 2021. Richmond City falls 25.0% in 2021 while schools with a total drop from 54 to 47. The causes are not established. Questions about "fastest-growing" or "fastest-shrinking" divisions can surface these artifacts.
3. **Schools reporting varies by year.** Schools with an all-grades total: 1,857 (2015), 2,112 to 2,121 (2018 to 2020), 1,948 (2021), 1,860 to 1,884 (2022 to 2024). Total students stay steady, so a division's "schools reporting" count must travel with its enrollment.
4. **Missing school totals.** 1 (2020), 5 (2021) and 15 (2022) schools have no enrollment value. Division totals for those years leave those schools out.
5. **Statewide Title I.** Title I fields exist for 2015-2021 only.
