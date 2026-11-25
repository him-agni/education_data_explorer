"""Prove the silver layer: bronze rows = silver rows + quarantined rows, no duplicate keys, IDs well-formed.

Usage:
    python scripts/check_silver.py
Exit code 0 when every check passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import os
import sys

# bronze table -> (silver tables that hold its good rows, quarantine source_table value)
BALANCES = {
    "bronze.ccd_directory": (["silver.school_year"], "bronze.ccd_directory"),
    "bronze.ccd_district_directory": (["silver.district_year"], "bronze.ccd_district_directory"),
    "bronze.ccd_enrollment": (["silver.enrollment", "silver.enrollment_total"], "bronze.ccd_enrollment"),
}

# silver table -> key columns that must be unique
KEYS = {
    "silver.school_year": ["ncessch", "year"],
    "silver.district_year": ["leaid", "year"],
    "silver.enrollment": ["ncessch", "year", "grade_code"],
    "silver.enrollment_total": ["ncessch", "year"],
}

# (silver table, id column, required length)
ID_LENGTHS = [
    ("silver.school_year", "ncessch", 12),
    ("silver.school_year", "leaid", 7),
    ("silver.district_year", "leaid", 7),
    ("silver.enrollment", "ncessch", 12),
    ("silver.enrollment", "leaid", 7),
    ("silver.enrollment_total", "ncessch", 12),
    ("silver.enrollment_total", "leaid", 7),
]


def balance_problem(bronze_rows: int, silver_rows: int, quarantine_rows: int) -> str | None:
    """None when bronze = silver + quarantine, otherwise a message with the gap."""
    accounted = silver_rows + quarantine_rows
    if bronze_rows == accounted:
        return None
    return (
        f"bronze {bronze_rows} != silver {silver_rows} + quarantine {quarantine_rows} "
        f"(= {accounted}); {bronze_rows - accounted:+d} rows unaccounted for"
    )


def one_number(client, warehouse_id: str, catalog: str, sql: str) -> int:
    import run_sql

    rows = run_sql.query_rows(client, warehouse_id, catalog, sql)
    return int(rows[0][0])


def main(argv: list[str] | None = None) -> int:
    from databricks.sdk import WorkspaceClient

    import run_sql

    parser = argparse.ArgumentParser(description="Check the silver layer.")
    parser.add_argument("--catalog", default="workspace")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    args = parser.parse_args(argv)
    client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    warehouse_id = run_sql.find_warehouse(client)

    def n(sql: str) -> int:
        return one_number(client, warehouse_id, args.catalog, sql)

    failed = False
    print("1. bronze = silver + quarantine")
    for bronze, (silvers, source) in BALANCES.items():
        b = n(f"SELECT COUNT(*) FROM {bronze}")
        s = sum(n(f"SELECT COUNT(*) FROM {t}") for t in silvers)
        q = n(f"SELECT COUNT(*) FROM silver.quarantine WHERE source_table = '{source}'")
        problem = balance_problem(b, s, q)
        print(f"   {'OK  ' if not problem else 'FAIL'} {bronze}: {b} = {s} silver + {q} quarantined")
        if problem:
            print(f"        {problem}")
            failed = True

    print("2. no duplicate keys")
    for table, cols in KEYS.items():
        key = ", ".join(cols)
        dupes = n(f"SELECT COUNT(*) FROM (SELECT {key} FROM {table} GROUP BY {key} HAVING COUNT(*) > 1)")
        print(f"   {'OK  ' if dupes == 0 else 'FAIL'} {table} ({key}): {dupes} duplicate keys")
        failed = failed or dupes != 0

    print("3. IDs are exactly the expected length")
    for table, column, length in ID_LENGTHS:
        bad = n(f"SELECT COUNT(*) FROM {table} WHERE {column} IS NULL OR length({column}) <> {length}")
        print(f"   {'OK  ' if bad == 0 else 'FAIL'} {table}.{column} = {length} chars: {bad} bad")
        failed = failed or bad != 0

    print("4. quarantine by reason")
    rows = run_sql.query_rows(
        client,
        warehouse_id,
        args.catalog,
        "SELECT source_table, reason, COUNT(*) FROM silver.quarantine GROUP BY 1, 2 ORDER BY 1, 2",
    )
    if not rows:
        print("   (empty: no rows were rejected)")
    for source, reason, count in rows:
        print(f"   {source} | {reason} | {count}")
    return 1 if failed else 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
