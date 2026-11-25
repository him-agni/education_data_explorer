# Metrics

Every number planned for the README or a resume goes here with how it was measured. Nothing here is a claim until its "How measured" column is filled in.

## Raw layer (Phases 1 and 4, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Years covered | 2015-2024 (10 school years) | Latest year with Virginia data checked against the live API: 2025 directory returns 0 rows, 2025 enrollment returns HTTP 500 |
| Raw files | 40 (10 each: directory, district directory, enrollment, enrollment by race) | `manifests/urban_manifest.json` |
| Raw rows | 323,523 (about 78.4 MB) across the 40 files | Sum of `rows` and `bytes` in `manifests/urban_manifest.json`, verified against the files in the Volume |
| Files matching manifest checksum, size and line count | 40 of 40 | Files copied from `/Volumes/workspace/bronze/raw/urban` and checked with sha256 |
| Years where individual grades sum to the grade-99 total | 10 of 10 | Sum of non-null enrollment over grades other than 99 vs the grade-99 rows, per year |
| Years where race groups sum to the grade-99 total | 10 of 10, and 0 mismatching school-years of 19,518 | Race groups vs race 99 vs by-grade total, statewide and school by school |
| Statewide total vs VDOE fall membership | within 0.35% for 2023 and 2024 (confirmed); 2022 unconfirmed | See `docs/data_dictionary.md` |

## Bronze layer (Phases 2 and 4, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| `bronze.ccd_directory` | 21,485 rows from 10 files | `scripts/check_bronze.py` (SQL `COUNT(*)` per `_source_file` vs manifest) |
| `bronze.ccd_district_directory` | 2,167 rows from 10 files | same |
| `bronze.ccd_enrollment` | 126,066 rows from 10 files | same |
| `bronze.ccd_enrollment_race` | 173,805 rows from 10 files | same |
| Files whose bronze row count equals the manifest | 40 of 40 | same |
| Rows added by re-running the load | 0 in the directory, district directory and enrollment tables (race loaded once) | `COPY INTO` result (`num_affected_rows` = 0) on a second run |
| Columns commented | 147 (54 directory + 71 district + 11 enrollment + 11 race), 0 without a comment | `DESCRIBE TABLE` after `scripts/comment_bronze.py` |
| Bronze values vs independent profile | grade-99 sums, null counts (2020: 2, 2021: 17, 2022: 211) and Title I coverage identical to the API profile | SQL aggregates on bronze vs numbers profiled directly from the API |

## Divisions (Phase 3, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Agencies in the 2024 Virginia directory | 209: 131 regular school divisions (type 1), 61 specialized, 17 state-operated | `bronze.ccd_district_directory` grouped by `agency_type` |
| Divisions (regular school district in any year) | 132 | `silver.district_year` where `is_school_division` |
| Students outside those 132 agencies | 97 to 315 per year (0.005% to 0.024%) | `silver.enrollment_total` joined to `silver.district_year` |

## Silver layer (Phases 3 and 4, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| `silver.school_year` | 21,485 rows | `scripts/check_silver.py` |
| `silver.district_year` | 2,167 rows | same |
| `silver.enrollment` + `silver.enrollment_total` | 106,548 + 19,518 = 126,066 rows (individual grades plus grade 99) | same |
| `silver.enrollment_race` + `silver.enrollment_race_total` | 154,287 + 19,518 = 173,805 rows (race groups plus race 99) | same |
| Rows quarantined on the real data | 0 of 323,523 bronze rows | `silver.quarantine` is empty |
| Bronze = silver + quarantine | 4 of 4 tables balance exactly | `scripts/check_silver.py` |
| Duplicate keys / wrong-length IDs in silver | 0 / 0 across 6 tables and 11 ID columns | same |
| Rejection rules proved with injected bad rows | All 9 enrollment reasons, the race rules (including zeros to missing), directory duplicate and bad-year, district state-mismatch | `tests/integration/test_silver_rules.py` (11 tests on scratch schemas) |
| School totals with null enrollment (status `missing`) | 2020: 1, 2021: 5, 2022: 15 | `silver.enrollment_total` where `enrollment_status <> 'reported'` |
| Race rows whose placeholder zero was set to missing | 168 (21 school-years x 8 race groups) | `silver.enrollment_race` where `enrollment_status = 'missing'` |
| Silver rebuild from bronze gives identical tables | 14 of 14 tables identical (row counts and row hashes), also from a fresh clone of the repo | Fingerprint before and after a full rebuild (measured before the race tables were added; the race tables are covered by the same SQL pattern but not yet fingerprinted) |

## Gold layer (Phase 4, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Gold tables | 6 | `scripts/check_gold.py` |
| Rows | state 10, division-year 1,317, school-year 21,485, division-grade 18,514, openings and closings 2,270, demographics 10,404 | `COUNT(*)` per table |
| Columns with a comment | 83 of 83 | `information_schema.columns` |
| Duplicate primary keys | 0 in all 6 tables | `scripts/check_gold.py` |
| Grade rows and race rows vs division total | 0 of 1,317 division-years differ, for both | `scripts/check_gold.py` |
| Division totals vs state total | gap 0.005% to 0.024% every year (limit set at 0.05%) | `scripts/check_gold.py` |
| Division-years flagged as large swings (15% or more) | 11 of 1,317 | `gold.division_year_enrollment` where `large_swing_flag` |
| Permanent school closings / schools opened / temporary closed status / agency changers | 121 / 117 / 10 / 2 | `gold.school_openings_closings` (opened = schools with an `opened_school_year`, 2015 to 2024) |

## Benchmark (Phase 4, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Questions | 46 in 26 groups | `eval/validate_questions.py` |
| Answerable base questions with gold SQL | 16, all run and return rows on the gold tables | `eval/validate_questions.py --live` |
| Tables joined per gold SQL | 15 of 16 gold SQL queries use 1 gold table and 1 uses 2 (the charter share question); a raw-table equivalent has not been measured | Count of `gold.` table names in each distinct gold SQL in `eval/questions.csv` |
| Split | 30 dev rows, 16 test rows (35%), phrasings of a question always in the same split | `eval/validate_questions.py` |
| Genie accuracy | not measured yet (no Genie space exists) | |

## Tests

| Metric | Value | How measured |
|---|---|---|
| Unit tests | 80 passing, 11 skipped (the skipped ones are the warehouse integration tests) | `pytest` |
| Integration tests | 11 passing against a warehouse | `RUN_WAREHOUSE_TESTS=1 pytest tests/integration` |
| Coverage | not measured yet | |

Data is small: exact row counts only, no "big data" claim.
