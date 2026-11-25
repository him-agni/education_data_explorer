"""Check that bronze row counts per source file equal the pull manifest.

This is the cheapest guard against a half-uploaded or half-loaded file.

Usage:
    python scripts/check_bronze.py --manifest manifests/urban_manifest.json
Exit code 0 when every file matches, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

# bronze table -> manifest dataset name
TABLES = {"bronze.ccd_directory": "directory", "bronze.ccd_enrollment": "enrollment"}


def relative_file_key(source_file: str) -> str:
    """'dbfs:/Volumes/c/bronze/raw/urban/ccd/x/fips=51/year=2015/part.jsonl' -> 'ccd/x/fips=51/...'"""
    marker = "/urban/"
    position = source_file.find(marker)
    if position == -1:
        return source_file
    return source_file[position + len(marker) :]


def expected_counts(manifest: dict, dataset: str) -> dict[str, int]:
    """Rows per file the manifest says were pulled for a dataset (empty pulls have no file)."""
    return {
        entry["file"]: int(entry["rows"])
        for entry in manifest["files"].values()
        if entry["dataset"] == dataset and entry["file"]
    }


def compare_counts(expected: dict[str, int], loaded: dict[str, int]) -> list[str]:
    """Return a list of problems (empty when bronze matches the manifest exactly)."""
    problems = []
    for file, rows in sorted(expected.items()):
        if file not in loaded:
            problems.append(f"missing in bronze: {file} (manifest says {rows} rows)")
        elif loaded[file] != rows:
            problems.append(f"row count differs: {file} manifest={rows} bronze={loaded[file]}")
    for file in sorted(set(loaded) - set(expected)):
        problems.append(f"in bronze but not in manifest: {file} ({loaded[file]} rows)")
    return problems


def loaded_counts(client, warehouse_id: str, catalog: str, table: str) -> dict[str, int]:
    import run_sql

    rows = run_sql.query_rows(
        client, warehouse_id, catalog, f"SELECT _source_file, COUNT(*) FROM {table} GROUP BY _source_file"
    )
    return {relative_file_key(path): int(count) for path, count in rows}


def main(argv: list[str] | None = None) -> int:
    from databricks.sdk import WorkspaceClient

    import run_sql

    parser = argparse.ArgumentParser(description="Compare bronze row counts with the manifest.")
    parser.add_argument(
        "--manifest", type=pathlib.Path, default=pathlib.Path("manifests/urban_manifest.json")
    )
    parser.add_argument("--catalog", default="workspace")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    parser.add_argument("--warehouse-id", default=None)
    args = parser.parse_args(argv)

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    warehouse_id = args.warehouse_id or run_sql.find_warehouse(client)

    failed = False
    for table, dataset in TABLES.items():
        expected = expected_counts(manifest, dataset)
        loaded = loaded_counts(client, warehouse_id, args.catalog, table)
        problems = compare_counts(expected, loaded)
        total_expected, total_loaded = sum(expected.values()), sum(loaded.values())
        status = "OK" if not problems else "MISMATCH"
        print(
            f"{status:9} {table}: {len(loaded)} files, {total_loaded} rows "
            f"(manifest: {len(expected)} files, {total_expected} rows)"
        )
        for problem in problems:
            print(f"          {problem}")
        failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
