# Metrics

Every number planned for the README or a resume goes here with how it was measured. Nothing here is a claim until its "How measured" column is filled in.

## Raw layer (Phase 1, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| Years covered | 2015-2024 (10 school years) | Latest year with Virginia data checked against the live API: 2025 directory returns 0 rows, 2025 enrollment returns HTTP 500 |
| Raw files | 20 (10 directory + 10 enrollment) | `manifests/urban_manifest.json` |
| Raw rows | 147,551 (about 47.0 MB) across the 20 files | Sum of `rows` and `bytes` in `manifests/urban_manifest.json`, verified against the files in the Volume |
| Files matching manifest checksum, size and line count | 20 of 20 | Files copied from `/Volumes/workspace/bronze/raw/urban` and checked with sha256 |
| Years where individual grades sum to the grade-99 total | 10 of 10 | Sum of non-null enrollment over grades other than 99 vs the grade-99 rows, per year |
| Statewide total vs VDOE fall membership | within 0.35% for 2023 and 2024 (confirmed); 2022 unconfirmed | See `docs/data_dictionary.md` |
| Unit tests | 50 passing (pull script, SQL runner, bronze check, comment builder). Coverage not measured yet | `pytest` |

## Bronze layer (Phase 2, measured 2026-11-25)

| Metric | Value | How measured |
|---|---|---|
| `bronze.ccd_directory` | 21,485 rows from 10 files | `scripts/check_bronze.py` (SQL `COUNT(*)` per `_source_file` vs manifest) |
| `bronze.ccd_enrollment` | 126,066 rows from 10 files | same |
| Files whose bronze row count equals the manifest | 20 of 20 | same |
| Rows added by re-running the load | 0 in both tables | `COPY INTO` result (`num_affected_rows` = 0) on the second run |
| Columns commented | 65 (54 directory + 11 enrollment), 0 without a comment | `DESCRIBE TABLE` after `scripts/comment_bronze.py` |
| Bronze values vs independent profile | grade-99 sums, null counts (2020: 2, 2021: 17, 2022: 211) and Title I coverage identical to the API profile | SQL aggregates on bronze vs numbers profiled directly from the API |

Data is small: exact row counts only, no "big data" claim.
