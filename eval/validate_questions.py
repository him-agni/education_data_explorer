"""Validate eval/questions.csv: structure, split hygiene, and (live) that every gold SQL runs on gold tables.

Structural rules are pure and unit-tested. The live part runs each distinct gold SQL once on the warehouse and
requires at least one row, which proves each question can be answered from the gold tables.

Usage:
    python eval/validate_questions.py            # structure only
    python eval/validate_questions.py --live     # also run every gold SQL
"""

from __future__ import annotations

import argparse
import csv
import os
import pathlib
import re
import sys

COLUMNS = ["id", "question", "group", "category", "split", "gold_sql", "expected"]
CATEGORIES = {
    "lookup",
    "ranking",
    "trend",
    "comparison",
    "derived measure",
    "ambiguous",
    "out of scope",
    "edge case",
}
SPLITS = {"dev", "test"}
EXPECTED = {"answer", "decline", "ask to clarify"}
FORBIDDEN_SCHEMAS = re.compile(r"\b(bronze|silver|ops)\s*\.", re.IGNORECASE)
MIN_ROWS = 30
TEST_SHARE_RANGE = (0.25, 0.45)


def load_rows(path: pathlib.Path) -> list[dict]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def validate_rows(rows: list[dict]) -> list[str]:
    """Return a list of problems (empty when the question set is sound)."""
    problems: list[str] = []
    if not rows:
        return ["no rows"]
    missing = [c for c in COLUMNS if c not in rows[0]]
    if missing:
        return [f"missing columns: {missing}"]

    ids = [r["id"] for r in rows]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"duplicate id {dup}")

    for r in rows:
        where = f"{r['id']} ({r['group']})"
        if not re.fullmatch(r"q\d{3}", r["id"]):
            problems.append(f"{where}: id must look like q001")
        if not r["question"].strip():
            problems.append(f"{where}: empty question")
        if r["category"] not in CATEGORIES:
            problems.append(f"{where}: unknown category {r['category']!r}")
        if r["split"] not in SPLITS:
            problems.append(f"{where}: unknown split {r['split']!r}")
        if r["expected"] not in EXPECTED:
            problems.append(f"{where}: unknown expected {r['expected']!r}")
        sql = r["gold_sql"].strip()
        if r["expected"] == "answer" and not sql:
            problems.append(f"{where}: expected 'answer' needs a gold_sql")
        if r["expected"] != "answer" and sql:
            problems.append(f"{where}: expected {r['expected']!r} must have an empty gold_sql")
        if sql:
            if not re.match(r"(?is)^\s*(select|with)\b", sql):
                problems.append(f"{where}: gold_sql must be a SELECT")
            if FORBIDDEN_SCHEMAS.search(sql):
                problems.append(f"{where}: gold_sql must use gold tables only")
            if ";" in sql.rstrip().rstrip(";"):
                problems.append(f"{where}: gold_sql must be one statement")

    # phrasings of one question must share split, category, expected and gold SQL (no leakage between splits)
    groups: dict[str, list[dict]] = {}
    for r in rows:
        groups.setdefault(r["group"], []).append(r)
    for group, members in sorted(groups.items()):
        for field in ("split", "category", "expected", "gold_sql"):
            if len({m[field] for m in members}) > 1:
                problems.append(f"group {group}: phrasings disagree on {field}")

    if len(rows) < MIN_ROWS:
        problems.append(f"only {len(rows)} rows; the plan asks for at least {MIN_ROWS}")
    test_share = sum(r["split"] == "test" for r in rows) / len(rows)
    low, high = TEST_SHARE_RANGE
    if not low <= test_share <= high:
        problems.append(f"test split is {test_share:.0%} of rows; expected {low:.0%} to {high:.0%}")
    return problems


def distinct_gold_sql(rows: list[dict]) -> dict[str, str]:
    """group -> gold SQL, one entry per group that has SQL."""
    return {r["group"]: r["gold_sql"].strip() for r in rows if r["gold_sql"].strip()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the benchmark question set.")
    parser.add_argument("--file", type=pathlib.Path, default=pathlib.Path("eval/questions.csv"))
    parser.add_argument("--live", action="store_true", help="also run every gold SQL on the warehouse")
    parser.add_argument("--catalog", default="workspace")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    args = parser.parse_args(argv)

    rows = load_rows(args.file)
    problems = validate_rows(rows)
    groups = {r["group"] for r in rows}
    print(f"{len(rows)} questions in {len(groups)} groups; structure problems: {len(problems)}")
    for problem in problems:
        print(f"  PROBLEM {problem}")
    failed = bool(problems)

    if args.live:
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
        from databricks.sdk import WorkspaceClient

        import run_sql

        client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
        warehouse_id = run_sql.find_warehouse(client)
        print("live: running each distinct gold SQL")
        for group, sql in sorted(distinct_gold_sql(rows).items()):
            try:
                result = run_sql.query_rows(client, warehouse_id, args.catalog, sql)
            except run_sql.SqlError as exc:
                print(f"  FAIL {group}: {str(exc)[:150]}")
                failed = True
                continue
            status = "OK  " if result else "FAIL"
            failed = failed or not result
            preview = " | ".join("NULL" if v is None else str(v) for v in result[0]) if result else "no rows"
            print(f"  {status} {group}: {len(result)} row(s); first: {preview[:90]}")
    return 1 if failed else 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
