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
