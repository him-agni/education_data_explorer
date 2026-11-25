# Decision log

Newest entries last. Phase 0 checks are in `docs/feasibility.md`.

## D-001: Years covered (2026-11-23)
Pull 2015-2024 for Virginia. 2024 is the latest year with data (2025 directory is empty and 2025 enrollment returns HTTP 500). Evidence: live API calls.

## D-002: State-ready design (2026-11-23)
All tables carry `state_fips` and `state_name`. Pull script and job take a list of states. Only Virginia (51) is loaded in v1. Decided with the project owner.

## D-003: Where the pull runs (2026-11-23)
`educationdata.urban.org` is reachable from a Databricks serverless notebook (HTTP 200). **Decision (project owner): the pull runs inside Databricks by default**, writing straight to `/Volumes/workspace/bronze/raw`, with no upload step. The script must also keep a local mode as a backup. Only one small page was tested so far, so a full multi-year pull inside Databricks is still to be proven.

## D-004: Title I scope (2026-11-23)
Title I fields are empty for 2022-2024 in the Virginia directory (populated 2015-2021). **Decision (project owner): keep the Title I benchmark question, scoped to 2015-2021.** Genie instructions must state that Title I data ends in 2021, and the benchmark also checks that Genie says so instead of guessing for later years.

## D-005: Data terms (2026-11-23)
Urban's data is under ODC-By v1.0. Attribution is required (cite the portal and the dataset). Urban asks to be notified of public projects. The plan still commits only the pull script and manifest, not raw files.

## D-006: Raw file layout (2026-11-25)
Files are written to `ccd/<dataset>/fips=<state>/year=<year>/part.jsonl` plus one `manifest.json`. The plan's layout was `ccd/<dataset>/year=<year>/`. The extra `fips=` level supports the state-ready design (D-002). All grade requests for one year go into one file per dataset (the `grade` field is in every row).

## D-007: Deterministic raw files (2026-11-25)
`pull_urban.py` sorts keys and rows before writing, uses LF line endings and UTF-8. Re-running on unchanged source data gives byte-identical files and the same sha256 (checked: second run of Virginia 2022 reported `unchanged`). Values are never altered. A file is rewritten only when its bytes change.
Known catch for Phase 2: `COPY INTO` remembers files by path. If Urban revises data and a file is re-pulled with new content at the same path, `COPY INTO` will skip it. Bronze loading must handle this on purpose (for example a forced reload, or rebuilding bronze from the manifest checksums).

## D-008: Grades requested (2026-11-25)
`enrollment` requests every codebook grade: `pk`, 0-15, 99, 999 (19 requests per year). Empty grades cost a request but protect against silently missing a grade in another year. `enrollment_race` requests only grade 99 (total) for v1.

## D-009: Full pull ran as a serverless Databricks job (2026-11-25)
`databricks jobs submit` ran `pull_urban.py` on serverless compute and wrote straight to `/Volumes/workspace/bronze/raw/urban`: Virginia 2015-2024, directory and enrollment, 20 files, 0 failures. All 20 files match their manifest checksums, sizes and line counts. Notes for the Phase 5 job definition:
- A serverless task needs an `environments` block and an `environment_key` on the task. `{"environment_version": "4"}` was accepted (an empty spec is rejected).
- Databricks' runtime reports `sys.exit(0)` as a failed task (SystemExit). The script now exits only on a non-zero code.
- On Windows Git Bash, set `MSYS_NO_PATHCONV=1` for `databricks api` and path arguments that start with `/`.

## D-010: Where the manifest is committed (2026-11-25)
The manifest produced by the Databricks run is committed as `manifests/urban_manifest.json` (public URLs, row counts, checksums, fetch times). Raw data files are not committed.

## D-011: Bronze load design (2026-11-25)
- Tables are created schema-less (`CREATE TABLE IF NOT EXISTS bronze.x;`) and `COPY INTO ... FORMAT_OPTIONS ('primitivesAsString'='true') COPY_OPTIONS ('mergeSchema'='true')` infers the columns. Confirmed to work on Free Edition. Result: all source columns are strings; only `_ingested_at` is a timestamp, `_source_file` is a string.
- `PATTERN = '*/*/part.jsonl'` is required for the `fips=<n>/year=<y>/part.jsonl` layout. `**/part.jsonl` fails with PATH_NOT_FOUND (each `*` matches one folder level).
- `_source_file` values look like `dbfs:/Volumes/<catalog>/bronze/raw/urban/ccd/<dataset>/fips=51/year=2015/part.jsonl`.
- SQL files use `${catalog}` and `${pulled_on}` placeholders, filled by `scripts/run_sql.py` (`--catalog`, `--set pulled_on=...`). A missing placeholder is an error, never a silent blank.
- Bronze column comments are generated from Urban's own codebook labels by `scripts/comment_bronze.py`.
- `scripts/check_bronze.py` compares rows per source file with the manifest (exit code 1 on any mismatch). It is the guard against a half-uploaded or half-loaded file and is a pure, unit-tested comparison.
- Still open (from D-007): what to do if Urban revises data and a file is re-pulled at the same path. `COPY INTO` would skip it. Current stance: detect via checksum vs manifest, and load revisions from a new path so silver's "keep the latest `_ingested_at`" rule picks the newest row.

## D-012: District directory pulled in v1; division = regular school district in any year (2026-11-25)
Supersedes the earlier plan to defer the district directory. The school directory has no agency type, so a count of "divisions" could only be guessed from names. The district directory has Urban's own `agency_type`. Facts from the data: 209 agencies in 2024 (131 regular local school districts, 61 specialized, 17 state-operated). 132 agencies are type 1 in at least one year. Greensville County and Williamsburg-James City County were type 3 (supervisory union) in 2015-2016. 62 agencies were relabelled from type 4 to type 9 in 2018.
Rule: `silver.district_year.is_school_division` is true when the agency is type 1 in ANY year. A per-year filter would leave about 14,267 students outside divisions in 2015; the any-year rule leaves 97. Decided with the project owner.
Consequence for gold: division tables use `is_school_division`. The state total includes every agency, so it matches VDOE. Division sums differ from the state total by 0.005% to 0.024%.

## D-013: Silver design (2026-11-25)
- Checks are written as views (`silver.v_*_checked`) that flag each bronze row with a reason, so the silver table and the quarantine insert read one definition of "bad".
- One quarantine table for all sources (`silver.quarantine`, with `source_table`, the raw key fields and the whole row as JSON). The plan named `quarantine_enrollment`; one table is simpler to count and to report on.
- Duplicate losers are quarantined with reason `duplicate_loser`, so the proof is bronze = silver + quarantine.
- Enrollment is split into `silver.enrollment` (individual grades) and `silver.enrollment_total` (grade 99), so the total can never be added to the grades.
- The state check compares ID prefixes with `fips` instead of hardcoding 51 (state-ready design, D-002).
- Dimension tables are generated from the codebook by `scripts/gen_dim_sql.py`, not typed by hand.
- Null enrollment is read as `missing` (see the data dictionary note).
- No staffing, finance or score columns are carried into silver.

## D-014: Silver rules are tested with injected bad rows (2026-11-25)
The real Virginia data is clean: 0 rows quarantined. A silent quarantine proves nothing about the rules, so `tests/integration/test_silver_rules.py` runs the real silver SQL against scratch schemas holding deliberately corrupted rows, then drops them. All 9 enrollment reasons fire once, the newer duplicate wins, special values map to NULL plus a status, and the any-year division rule holds. The test needs a warehouse, so it is skipped unless `RUN_WAREHOUSE_TESTS=1` (CI cannot run it).
