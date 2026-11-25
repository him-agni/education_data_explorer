# Metrics

Every number planned for the README or a resume goes here with how it was measured. Nothing here is a claim until its "How measured" column is filled in.

## Raw layer (Phase 1, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Years covered | 2015-2024 (10 school years) | Latest year with Virginia data checked against the live API: 2025 directory returns 0 rows, 2025 enrollment returns HTTP 500 |
| Raw files | 30 (10 directory + 10 district directory + 10 enrollment) | `manifests/urban_manifest.json` |
| Raw rows | 149,718 (about 51.3 MB) across the 30 files | Sum of `rows` and `bytes` in `manifests/urban_manifest.json`, verified against the files in the Volume |
| Files matching manifest checksum, size and line count | 30 of 30 | Files copied from `/Volumes/workspace/bronze/raw/urban` and checked with sha256 |
| Years where individual grades sum to the grade-99 total | 10 of 10 | Sum of non-null enrollment over grades other than 99 vs the grade-99 rows, per year |
| Statewide total vs VDOE fall membership | within 0.35% for 2023 and 2024 (confirmed); 2022 unconfirmed | See `docs/data_dictionary.md` |
| Unit tests | 64 passing, plus 8 integration tests that need a warehouse. Coverage not measured yet | `pytest` |

## Bronze layer (Phase 2, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| `bronze.ccd_directory` | 21,485 rows from 10 files | `scripts/check_bronze.py` (SQL `COUNT(*)` per `_source_file` vs manifest) |
| `bronze.ccd_district_directory` | 2,167 rows from 10 files | same |
| `bronze.ccd_enrollment` | 126,066 rows from 10 files | same |
| Files whose bronze row count equals the manifest | 30 of 30 | same |
| Rows added by re-running the load | 0 in all three tables | `COPY INTO` result (`num_affected_rows` = 0) on a second run |
| Columns commented | 136 (54 directory + 71 district + 11 enrollment), 0 without a comment | `DESCRIBE TABLE` after `scripts/comment_bronze.py` |
| Bronze values vs independent profile | grade-99 sums, null counts (2020: 2, 2021: 17, 2022: 211) and Title I coverage identical to the API profile | SQL aggregates on bronze vs numbers profiled directly from the API |

## Divisions (Phase 3, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Agencies in the 2024 Virginia directory | 209: 131 regular school divisions (type 1), 61 specialized, 17 state-operated | `bronze.ccd_district_directory` grouped by `agency_type` |
| Divisions (regular school district in any year) | 132 | `silver.district_year` where `is_school_division` |
| Students outside those 132 agencies | 97 to 315 per year (0.005% to 0.024%) | `silver.enrollment_total` joined to `silver.district_year` |

## Silver layer (Phase 3, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| `silver.school_year` | 21,485 rows | `scripts/check_silver.py` |
| `silver.district_year` | 2,167 rows | same |
| `silver.enrollment` + `silver.enrollment_total` | 126,066 rows (individual grades plus grade 99) | same |
| Rows quarantined on the real data | 0 of 149,718 bronze rows | `silver.quarantine` is empty |
| Bronze = silver + quarantine | 3 of 3 tables balance exactly | `scripts/check_silver.py` |
| Duplicate keys / wrong-length IDs in silver | 0 / 0 across 4 tables and 7 ID columns | same |
| Rejection rules proved with injected bad rows | All 9 enrollment reasons, plus directory duplicate and bad-year and district state-mismatch | `tests/integration/test_silver_rules.py` (8 tests on scratch schemas) |
| School totals with null enrollment (status `missing`) | 2020: 1, 2021: 5, 2022: 15 | `silver.enrollment_total` where `enrollment_status <> 'reported'` |

Data is small: exact row counts only, no "big data" claim.
