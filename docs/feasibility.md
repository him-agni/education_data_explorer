# Feasibility checks

First page of the decision log. Each check is recorded with its date and result.

| # | Check | Date | Result | Notes |
|---|---|---|---|---|
| 1 | Genie works on the workspace (tiny table, one question) | 2026-11-23 | pass | Created a Genie agent (the UI now says "Genie Agents"; docs say "space") via "Connect sources manually" on `workspace.default.genie_test` (4 made-up rows). Asked which division had the biggest drop from 2022 to 2023. It answered correctly (Beta Division, -100, and noted Alpha +50) and quickly. The answer showed a "Thought process" section and a SQL icon (SQL not inspected). |
| 2 | An app can call Genie (hello-world Streamlit) | 2026-11-23 | pass | Deployed app `genie-hello` (Genie space attached as resource key `genie-space`) returned status COMPLETED in 27.1 s with the correct answer and the SQL. First attempt FAILED (`MessageStatus.FAILED`) until the app's service principal was granted SELECT on the test table, as the plan predicted. The Apps UI had no "Edit/Configure" step: resources are added from the app's Settings area, and the Genie resource permission defaulted to "Can edit", whereas the plan wants "Can run". The Apps tab under Compute is replaced by the app switcher (grid icon). Earlier notes: | API half passes: `databricks genie list-spaces` works, and `databricks genie start-conversation` on the test space returned status COMPLETED in about 19.6 s wall time. The reply has `attachments` holding a `text` answer and a `query` (SQL plus description), plus `query_result`. Generated SQL was correct. This ran as the user, not as an app service principal. App half: hello-world app in `feasibility/hello_genie_app/` created as app `genie-hello` and deployed (SNAPSHOT mode, "App started successfully") with `databricks apps create`, `workspace import-dir` and `apps deploy --source-code-path`. Still to test: attach the Genie space as resource key `genie-space`, redeploy, and click the button. |
| 3 | Urban's site is reachable from a Databricks notebook | 2026-11-23 | pass | Serverless notebook: `requests.get("https://educationdata.urban.org/api/v1/schools/ccd/directory/2022/", params={"fips": 51})` returned status 200 and count 2163 (about 10 s). So `educationdata.urban.org` is not blocked. The pull can run inside Databricks and write straight to the Volume, with a local run as the backup. Only the first page was requested, so large multi-page pulls are still to be tested. |
| 4 | SQL warehouse starts and runs a query | 2026-11-23 | pass | "Serverless Starter Warehouse" (2XS) started and `SELECT current_catalog();` ran in about 2 seconds in the SQL Editor. Returned `workspace`. Later, `current_date()` also ran through the SQL Statements API via the CLI (returned 2026-11-23). On Windows Git Bash, set `MSYS_NO_PATHCONV=1` before `databricks api` calls, or `/api/...` is rewritten to a Windows path and returns "Not Found". |
| 5 | Tooling connects (CLI login, folder sync) | 2026-11-23 | pass (login and Volume path) | CLI v1.24.0 logged in with profile `dbc-bc1b7c53-b562` (valid). `databricks catalogs list`, `schemas create`, `volumes create` and `fs ls` on the Volume path all worked. Folder sync was not tested. Python 3.10.2 and `requests` 2.32.5 are available. |

## Objects created (2026-11-23, via CLI, approved by user)

- Schemas: `workspace.bronze`, `workspace.silver`, `workspace.gold`, `workspace.ops`
- Managed Volume: `workspace.bronze.raw` (path `/Volumes/workspace/bronze/raw`)
- SQL warehouse: "Serverless Starter Warehouse", 2X-Small, ID `84023751bf89059c`

## Workspace facts to record

- Catalog name: `workspace` (confirmed 2026-11-23 via `SELECT current_catalog();`). Catalog Explorer also lists `system` and a shared `samples` catalog.
- Workspace URL: https://dbc-bc1b7c53-b562.cloud.databricks.com
- LinkedIn verification: pending (user). The workspace shows a "Continue verification" banner.
- App quota on this account (docs say up to 3; some forum posts say 1): pending

## Urban Institute API (checked 2026-11-22 through a fetch tool, not from the user's machine or Databricks)

- Metadata lists CCD school directory, school enrollment by grade and race, and school-districts directory for 1986-2024.
- Correction (2026-11-23): the codebook (`api-endpoints`, endpoint 25) lists `/schools/ccd/enrollment/{year}/{grade}/` ("By grade") as well as the `/race/`, `/sex/` and `/race/sex/` variants. The plan's `grade-{n}` pattern is valid (example `grade-8`). My earlier doubt about it was wrong.
- A test call to `.../enrollment/2022/grade-99/?fips=51` returned rows with fields year, ncessch, ncessch_num, grade, race, sex, enrollment, fips, leaid.
- Phase 1 findings are in `docs/data_dictionary.md` and `docs/decision_log.md`.

## Phase 0 outcome (2026-11-23)

All five checks pass. No fallback is needed: Genie works on this workspace and a deployed app can call it.

- Genie fallback: not needed.
- Urban is reachable from Databricks, so the pull script can run in a job as well as locally.
- Least privilege for the real app: the service principal needs SELECT on the tables Genie reads, and the Genie resource permission should be "Can run", not the UI default "Can edit".
- Cold start observed: about 27 s for the first app question.

## Cleanup (2026-11-23, approved by user)

- Dropped table `workspace.default.genie_test`.
- Deleted the test Genie space (only the built-in "Bakehouse Sales Starter Space" remains).
- Deleted app `genie-hello` (status was DELETING at the last check). The source is kept in `feasibility/hello_genie_app/`.
- Not removed, not asked about: the workspace folder `genie-hello-app` and the scratch notebook "New Notebook 2026-11-23 10:53:08".
