"""Add column comments to the bronze tables from Urban's own codebook labels.

Each comment reads "<Urban label>. Raw string, as delivered by Urban Institute, pulled on <date>."
Lineage columns get their own wording. Safe to re-run: comments are simply replaced.

Usage:
    python scripts/comment_bronze.py --pulled-on 2026-11-25
"""

from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import re
import sys

TABLES = [
    "bronze.ccd_directory",
    "bronze.ccd_district_directory",
    "bronze.ccd_enrollment",
    "bronze.ccd_enrollment_race",
]
LINEAGE = {
    "_source_file": "Lineage: path of the raw file this row was loaded from.",
    "_ingested_at": "Lineage: timestamp when this row was loaded into bronze.",
}


def load_labels(codebook_path: pathlib.Path) -> dict[str, str]:
    """variable name -> cleaned label, from Urban's api-variables.json."""
    results = json.loads(codebook_path.read_text(encoding="utf-8"))["results"]
    return {item["variable"]: clean_text(item["label"]) for item in results if item.get("label")}


def clean_text(text: str) -> str:
    """Remove HTML tags and entities and collapse whitespace."""
    text = html.unescape(re.sub(r"<[^>]+>", " ", text))
    return " ".join(text.replace("�", "-").split())


def build_comment(column: str, labels: dict[str, str], pulled_on: str) -> str:
    if column in LINEAGE:
        return LINEAGE[column]
    label = labels.get(column)
    suffix = f"Raw string, as delivered by Urban Institute, pulled on {pulled_on}."
    if label:
        return f"{label.rstrip('.')}. {suffix}"
    return f"No label in the Urban codebook. {suffix}"


def sql_literal(text: str) -> str:
    """A single-quoted SQL string literal (quotes doubled)."""
    return "'" + text.replace("'", "''") + "'"


def comment_statement(table: str, column: str, comment: str) -> str:
    return f"ALTER TABLE {table} ALTER COLUMN `{column}` COMMENT {sql_literal(comment)}"


def main(argv: list[str] | None = None) -> int:
    from databricks.sdk import WorkspaceClient

    import run_sql

    parser = argparse.ArgumentParser(description="Comment bronze columns from the Urban codebook.")
    parser.add_argument("--pulled-on", required=True, help="pull date, YYYY-MM-DD")
    parser.add_argument(
        "--codebook", type=pathlib.Path, default=pathlib.Path("docs/codebook/api-variables.json")
    )
    parser.add_argument("--catalog", default="workspace")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    args = parser.parse_args(argv)

    labels = load_labels(args.codebook)
    client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    warehouse_id = run_sql.find_warehouse(client)
    for table in TABLES:
        described = run_sql.query_rows(client, warehouse_id, args.catalog, f"DESCRIBE TABLE {table}")
        columns = [row[0] for row in described if row[0] and not row[0].startswith("#")]
        for column in columns:
            comment = build_comment(column, labels, args.pulled_on)
            run_sql.run_statement(
                client, warehouse_id, args.catalog, comment_statement(table, column, comment)
            )
        print(f"commented {len(columns)} columns on {table}")
    return 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
