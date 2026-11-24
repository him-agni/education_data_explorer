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
