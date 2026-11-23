# Education Data Explorer: Final Build Plan

Written for: Himani (project owner and sole builder). Nothing has been built yet. The repo folder `c:\dev\education_data_explorer` is empty and is not yet a git repo.

## Context

Build a pipeline and natural-language interface over public school data from the Urban Institute Education Data API. Virginia (FIPS 51) is loaded first. The design is state-ready, so other states are added later by changing a parameter, not code. Data lands in Delta tables (bronze, silver, gold) on Databricks Free Edition. A Genie space and a Databricks App then answer plain-English questions with plain-English answers, the generated SQL, and a "data as of" date. The proof of quality is a measured accuracy score on a held-out question set. The source plan is the Nov 22, 2026 "Education Data Explorer (Virginia)" document, with the decisions below layered on top.

## Decisions made with you

| Topic | Decision |
|---|---|
| Workspace | Free Edition account exists. Nothing built yet (no schemas, Volume or CLI login). |
| Working style | Step by step. I do one phase, then stop for your review before the next. |
| Years | 2015 to the latest year with real Virginia data, confirmed in Phase 1. |
| Multi-state | State-ready design. Tables carry `state_fips` and `state_name`. The pull script and job take a list of states. Only 51 is loaded in v1. |
| GitHub | You create the private repo and give me the URL. I run only local git commands, each after your approval. |
| Genie fallback | Decided after Phase 0 results. |
| Seed questions | The 9 seed bullets in the source plan, plus phrasings and 6 more base questions I propose for your review. |
| Pace | 10-12 hours a week, about 6-8 weeks. The calendar is in the Timeline section. |
| Portfolio | README and evaluation report, demo video script, Substack/LinkedIn draft, resume bullets and a one-page case study. |
| Plan delivery | This plan file, copied to `docs/build_plan.md` once you approve and the build begins. |

### My recommendation for v1 scope (you asked "what do you suggest?")

- **In v1:**
  - Race enrollment and the `division_year_demographics` gold table. A benchmark question depends on them.
  - The Genie API eval harness (`eval/run_eval.py`). It gives the latency metric and lets us test out-of-scope refusals at scale.
- **After v1.0.0:**
  - The district directory table. The school directory should already carry division names, so this is not needed yet.
  - Lakeflow pipeline expectations. The SQL assertions already meet every quality rule, so expectations are a learning exercise. I'd add them as a v1.1 note.

If you disagree with either, say so at the approval prompt.

## Facts I verified, and facts still to verify

Checked against live pages on 2026-11-22:
- The Urban API metadata lists CCD school directory, school enrollment by grade and race, and school-districts directory for **1986-2024**. The source plan said "through 2023", so use the API's figure.
- The enrollment endpoint is documented as `/schools/ccd/enrollment/{year}/{grade}/race/`. It takes `year` and `grade` and has no `sex` argument. The source plan's `grade-{n}` pattern may be wrong.
- A test call to `.../enrollment/2022/grade-99/?fips=51` returned rows with fields `year, ncessch, ncessch_num, grade, race, sex, enrollment, fips, leaid`. The first rows had `enrollment: null`, `grade: 99`, `race: 99`, `sex: 99`.
- Free Edition: up to 3 apps per account, apps stop 24 hours after start or redeploy, max 5 concurrent job tasks, one 2X-Small SQL warehouse, one active pipeline per type. Outbound internet is limited to trusted domains with no published list. The page says nothing on Genie, Asset Bundles or CLI tokens, so those are tested in Phase 0.

Still unverified, so Phase 0 and Phase 1 must settle them. I have not assumed any of these:
1. Exact enrollment endpoint path and grade codes, and how a "total/all grades" row appears (99 appears in the test call). Source: the `api-variables` metadata.
2. Whether `year` means the fall of the school year (for example 2019 = 2019-20). Source: the codebook. Genie instructions must state it.
3. Missing-value codes (-1, -2, -3 and any others). Source: the codebook. The null enrollment seen above may be Urban's own encoding for missing or suppressed.
4. Whether the directory carries a Title I field. If not, the Title I benchmark question is dropped.
5. Whether `ncessch` loses its leading zero. In the test call it came back as a string, plus a separate numeric `ncessch_num`, which differs from what the source plan describes. The padding rule may still be needed.
6. The latest year with real Virginia data.
7. Your catalog name, LinkedIn verification status, and whether the CLI is logged in.
8. The email for job-failure alerts. I will ask for it in Phase 5.

## Repo layout (as in the source plan, plus state parameterization)

```
education-data-explorer/
  README.md
  docs/  feasibility.md  decision_log.md  data_dictionary.md  runbook.md  metrics.md  build_plan.md
         codebook/  eval/changelog.md
  scripts/pull_urban.py        # runs locally, takes --states and --years
  sql/   bronze/ silver/ gold/ governance/ ops/
  jobs/                        # job and bundle definitions
  eval/  questions.csv  run_eval.py
  app/   app.py genie_client.py results.py events.py app.yaml
  tests/
  .github/workflows/ci.yml
```

Naming: one catalog, schemas `bronze`, `silver`, `gold`, `ops`. Plain-word table names such as `division_year_enrollment`. Every table keeps `state_fips`.

## Phases (each one ends with your review before the next starts)

### Phase 0: Setup and feasibility (days 1-2)
- Run the five checks from the source plan and record dated results in `docs/feasibility.md`:
  1. Genie on a tiny table.
  2. A hello-world app calling the Genie API.
  3. Urban reachable from a Databricks notebook.
  4. SQL warehouse `SELECT current_date()`.
  5. CLI login and folder sync.
- Setup tasks, split between us:
  - You: LinkedIn verification, create the private GitHub repo, tell me the catalog name.
  - Me, after approval: create the `bronze`, `silver`, `gold` and `ops` schemas and the `raw` Volume via CLI or SQL; `git init` locally; add the remote once you give the URL.
- **Gate:** the results decide the Genie fallback (hosted-model text-to-SQL or read-only dashboard). You choose then.

### Phase 1: Pull data (week 1)
1. Fetch the three metadata endpoints into `docs/codebook/`. Resolve unverified items 1-6 above.
2. Write `scripts/pull_urban.py`: loop over states, datasets and years, follow `next`, retry, pause, write one JSON Lines file per dataset, state and year, plus a `manifest.json` (URL, fetch time, row count, checksum).
3. Pull the school directory and enrollment first. Pull enrollment by race in the week-3 slot.
4. Compare statewide enrollment for one year with Virginia Department of Education fall membership. I will find that figure and show you the source.
5. Upload to the Volume. Write the missing-value code list into `docs/data_dictionary.md` before any cleaning.
6. Read Urban's Data Policy and Terms. Raw data is not committed. Only the script and manifest are.

### Phase 2: Bronze (week 2)
- All-string tables with `_source_file` and `_ingested_at`, append-only. `COPY INTO` from the Volume, or a PySpark all-string append if `COPY INTO` fails on Free Edition.
- Tables: `bronze.ccd_directory`, `bronze.ccd_enrollment`, later the race table.
- Reconcile row counts per file against the manifest. A re-run must add zero rows. Comments read "raw, as delivered by Urban Institute, pulled on <date>".
- Add the bronze row-count test.

### Phase 3: Silver (weeks 2-3)
- Steps in order: ID fix (only where verified needed), `try_cast`, special values to NULL plus a status column, keep the all-grades row separate, dedupe on school, year and grade, state filter, lookup tables decoded from the codebook, quarantine with a reason.
- Tables: `silver.school_year`, `silver.enrollment`, `silver.enrollment_race`, `dim_grade`, `dim_locale`, `dim_school_level`, `quarantine_enrollment`.
- Full rebuild with `CREATE OR REPLACE`. The reason goes in the decision log: small data, easier to test.
- Checks: no duplicate keys, ID lengths correct, bronze = silver + quarantine + duplicates removed.

### Phase 4: Gold (weeks 3-4)
- Tables: `state_year_enrollment`, `division_year_enrollment`, `school_year_profile`, `division_year_grade`, `school_openings_closings`, `division_year_demographics`.
- One grain per table. Plain column names. Year-over-year and percent change as columns. Informational primary and foreign keys. Comments on every table and column, with synonyms (division, district, LEA).
- Reconciliation of grade sums against the all-grades row.
- Write the benchmark questions and gold SQL now, before Genie exists. Add any missing table before Phase 6.

### Phase 5: Data quality and orchestration (week 4)
- SQL assertion rules as in the source plan, written to `ops.dq_results`. Thresholds are set after seeing real data, with reasons in the decision log.
- `ops.run_log` gets one row per step.
- Lakeflow job: ingest bronze, build silver, build gold, quality checks, publish comments. Parameters: `states` and `years`. Failure alert to the email you give me then.
- Test with a deliberately corrupted file. Confirm the right rule fails and the job stops.

### Phases 6-7: Genie space and evaluation (weeks 4-5)
- Space over gold tables only, with instructions, synonyms, about 10 example SQL patterns, and sample questions.
- `eval/questions.csv`: about 15 base questions with 2-3 phrasings each (35-45 rows), plus 6-8 out-of-scope questions. About one third is held out as `test` and is run once at the end.
- Loop: baseline with comments only, change one thing, rerun, log in `docs/eval/changelog.md`, tag each failure. Stop when dev accuracy plateaus, then report the test number.
- `eval/run_eval.py` asks each question through the Genie API, compares result sets, and writes `ops.genie_eval_runs` with latency. The comparison logic is a pure function with unit tests.

### Phase 8: App (weeks 5-6)
- Streamlit app with `genie_client.py`, `results.py` and `events.py`, as in the source plan: chat with example buttons, answer text, table, chart, SQL expander, "data as of", scope guard, retry on failure, thumbs feedback to `ops.app_events`, per-session question limit, and a footer crediting the Urban Institute and NCES.
- Unit tests with mocked Genie replies for the no-query, error and timeout cases.
- Phone-width layout and keyboard-only use.

### Phase 9: Security, CI and deploy (weeks 6-7)
- Least-privilege grants as code in `sql/governance/grants.sql`. The app gets SELECT on gold only.
- CI on GitHub Actions: `ruff`, `sqlfluff`, `pytest`, `gitleaks`. No tokens stored in GitHub.
- Deploy from your computer: run the job, create and deploy the app, attach resources, smoke-test three known questions. Tag `v1.0.0` with release notes.
- Write the runbook. Then a teardown-and-rebuild rehearsal from the README alone.

### Phase 10: Docs and portfolio (weeks 7-8)
- README in the source plan's order, the evaluation report, and `docs/metrics.md` with every number and how it was measured.
- Demo video script (shot list for the 3-minute video, which you record), Substack/LinkedIn draft, resume bullets, and a one-page case study.

## Timeline (10-12 hours/week, starting after approval)

| Weeks | Work |
|---|---|
| 1 | Phase 0, then Phase 1 |
| 2 | Phases 2 and 3 |
| 3 | Phases 3 and 4, plus race data |
| 4 | Phases 4 and 5, plus benchmark questions written |
| 5 | Phases 6 and 7 |
| 6 | Phase 7 finish, Phase 8 |
| 7 | Phase 9 |
| 8 | Phase 10 and buffer |

Cleaning and Genie tuning are the phases most likely to run long. Phases overlap as in the source plan.

## Definition of done (from the source plan)

- [ ] Re-running from raw files gives identical gold tables.
- [ ] Every data-quality rule passes, and the run log shows rows in, quarantined and out.
- [ ] Genie accuracy is reported with failures explained.
- [ ] The app answers questions end to end and declines out-of-scope ones.
- [ ] A stranger can understand the README in five minutes.
- [ ] `docs/metrics.md` holds every resume number with how it was measured.

## Verification

- Phase 1: manifest row counts, and statewide enrollment compared to a VDOE figure.
- Phases 2-4: SQL reconciliation queries (bronze = silver + quarantine + dupes) run through the SQL warehouse.
- Phase 5: corrupted-file test, and an identical-row-count rebuild.
- Phases 6-7: eval run history in `ops.genie_eval_runs` and `docs/eval/changelog.md`.
- Phase 8: `pytest` plus a manual smoke test in the live app.
- Phase 9: CI green and a README-only rebuild rehearsal.

## Risks

- Genie may be unavailable or unreliable on Free Edition, which is handled by the Phase 0 gate.
- The daily quota may run out, so heavy jobs run early in the day.
- The Urban API may be slow or change, so the pull is parameterized and logged in a manifest.
- Accuracy may stall, in which case we report the plateau honestly with a failure analysis.
- The account may be deleted for inactivity, so the repo stays the source of truth.
- Nobody outside your workspace can open the app, so the demo video and screenshots serve as the public view.
