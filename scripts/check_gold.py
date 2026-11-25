"""Check the gold layer: documentation, keys, reconciliation and naming.

Checks:
  1. every column of every gold table has a comment
  2. primary keys are unique and informational constraints exist
  3. grade rows and race rows add up to the division total, every division and year
  4. the division totals are within a small share of the state total (agencies outside divisions are small)
  5. one division name per division ID (the latest-name rule)

Usage:
    python scripts/check_gold.py
Exit code 0 when every check passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import os
import sys

# gold table -> primary key columns
KEYS = {
    "gold.state_year_enrollment": ["state_fips", "school_year"],
    "gold.division_year_enrollment": ["leaid", "school_year"],
    "gold.school_year_profile": ["ncessch", "school_year"],
    "gold.division_year_grade": ["leaid", "school_year", "grade_code"],
    "gold.school_openings_closings": ["ncessch"],
    "gold.division_year_demographics": ["leaid", "school_year", "race_code"],
}

# Divisions leave out regional, specialized and state-operated agencies. In Virginia 2015-2024 that is at most
# 0.024% of students, so a gap above this threshold means a join or filter went wrong.
MAX_DIVISION_GAP_PCT = 0.05


def percent_gap(state_total: int, division_total: int) -> float:
    """Share (in percent) of the state total that the division total leaves out."""
    if state_total == 0:
        return 0.0
    return 100.0 * (state_total - division_total) / state_total


def gap_problems(rows: list[tuple[int, int, int]], limit: float = MAX_DIVISION_GAP_PCT) -> list[str]:
    """rows are (school_year, state_total, division_total). Returns one message per year over the limit."""
    problems = []
    for year, state_total, division_total in rows:
        gap = percent_gap(state_total, division_total)
        if gap > limit or gap < 0:
            problems.append(f"{year}: divisions {division_total} vs state {state_total} (gap {gap:.3f}%)")
    return problems


def main(argv: list[str] | None = None) -> int:
    from databricks.sdk import WorkspaceClient

    import run_sql

    parser = argparse.ArgumentParser(description="Check the gold layer.")
    parser.add_argument("--catalog", default="workspace")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    args = parser.parse_args(argv)
    client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    warehouse_id = run_sql.find_warehouse(client)

    def rows(sql: str) -> list[list]:
        return run_sql.query_rows(client, warehouse_id, args.catalog, sql)

    def number(sql: str) -> int:
        return int(rows(sql)[0][0])

    failed = False

    def report(ok: bool, message: str) -> None:
        nonlocal failed
        print(f"   {'OK  ' if ok else 'FAIL'} {message}")
        failed = failed or not ok

    print("1. every gold column has a comment")
    for table in KEYS:
        schema, name = table.split(".")
        missing = rows(
            "SELECT column_name FROM information_schema.columns "
            f"WHERE table_schema = '{schema}' AND table_name = '{name}' "
            "AND (comment IS NULL OR trim(comment) = '')"
        )
        total = number(
            "SELECT COUNT(*) FROM information_schema.columns "
            f"WHERE table_schema = '{schema}' AND table_name = '{name}'"
        )
        report(not missing, f"{table}: {total - len(missing)} of {total} columns commented")
        for (column,) in missing:
            print(f"        missing comment: {column}")

    print("2. primary keys are unique and constraints exist")
    for table, cols in KEYS.items():
        key = ", ".join(cols)
        dupes = number(f"SELECT COUNT(*) FROM (SELECT {key} FROM {table} GROUP BY {key} HAVING COUNT(*) > 1)")
        schema, name = table.split(".")
        constraints = number(
            "SELECT COUNT(*) FROM information_schema.table_constraints "
            f"WHERE table_schema = '{schema}' AND table_name = '{name}' AND constraint_type = 'PRIMARY KEY'"
        )
        report(
            dupes == 0 and constraints == 1,
            f"{table} ({key}): {dupes} duplicate keys, primary key declared: {constraints == 1}",
        )

    print("3. grade rows and race rows add up to the division total")
    for label, table, measure in [
        ("grade", "gold.division_year_grade", "enrollment"),
        ("race", "gold.division_year_demographics", "enrollment"),
    ]:
        differing = number(
            f"""
            WITH parts AS (
              SELECT leaid, school_year, SUM({measure}) AS total FROM {table} GROUP BY leaid, school_year
            )
            SELECT COUNT(*) FROM gold.division_year_enrollment AS d
            LEFT JOIN parts AS p ON p.leaid = d.leaid AND p.school_year = d.school_year
            WHERE NOT (p.total <=> d.total_enrollment)
            """
        )
        report(differing == 0, f"{label} rows vs division total: {differing} division-years differ")

    print(f"4. division totals within {MAX_DIVISION_GAP_PCT}% of the state total")
    gap_rows = [
        (int(y), int(s), int(d))
        for y, s, d in rows(
            "SELECT s.school_year, s.total_enrollment, SUM(d.total_enrollment) "
            "FROM gold.state_year_enrollment s "
            "JOIN gold.division_year_enrollment d ON d.school_year = s.school_year "
            "GROUP BY s.school_year, s.total_enrollment ORDER BY 1"
        )
    ]
    problems = gap_problems(gap_rows)
    report(not problems, f"{len(gap_rows)} years checked, {len(problems)} over the limit")
    for problem in problems:
        print(f"        {problem}")

    print("5. one name per division ID")
    many = number(
        "SELECT COUNT(*) FROM (SELECT leaid FROM gold.division_year_enrollment GROUP BY leaid "
        "HAVING COUNT(DISTINCT division_name) > 1)"
    )
    report(many == 0, f"{many} division IDs have more than one name")
    return 1 if failed else 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
