"""Run the repo's .sql files on a Databricks SQL warehouse, one statement at a time.

Files use two-part names (bronze.ccd_enrollment) and the placeholder ${catalog}
where a full path is unavoidable (for example Volume paths). The catalog is also
set as the session catalog, so two-part names resolve inside it.

Usage:
    python scripts/run_sql.py sql/bronze/010_ccd_directory.sql --catalog workspace
    python scripts/run_sql.py sql/bronze/*.sql --profile my-profile --warehouse-id abc123

Auth uses the Databricks CLI profile (--profile, or DATABRICKS_CONFIG_PROFILE).
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import sys
import time

PLACEHOLDER = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")
TERMINAL_STATES = {"SUCCEEDED", "FAILED", "CANCELED", "CLOSED"}


class SqlError(Exception):
    """A statement failed, or a placeholder had no value."""


def split_statements(text: str) -> list[str]:
    """Split SQL text on semicolons that are outside quotes and comments.

    Comments are dropped. Handles '...' strings (with '' escapes), "..." and `...`
    identifiers, -- line comments and /* ... */ block comments.
    """
    statements: list[str] = []
    current: list[str] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if ch == "-" and nxt == "-":  # line comment
            while i < n and text[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":  # block comment
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            current.append(" ")
            continue
        if ch in ("'", '"', "`"):  # quoted string or identifier
            quote = ch
            current.append(ch)
            i += 1
            while i < n:
                current.append(text[i])
                if text[i] == quote:
                    if i + 1 < n and text[i + 1] == quote:  # doubled quote = escaped
                        current.append(text[i + 1])
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        if ch == ";":
            _flush(current, statements)
            i += 1
            continue
        current.append(ch)
        i += 1
    _flush(current, statements)
    return statements


def _flush(current: list[str], statements: list[str]) -> None:
    statement = "".join(current).strip()
    if statement:
        statements.append(statement)
    current.clear()


def render(statement: str, variables: dict[str, str]) -> str:
    """Replace ${name} placeholders. A placeholder with no value is an error."""

    def substitute(match: re.Match) -> str:
        name = match.group(1)
        if name not in variables:
            raise SqlError(f"no value for placeholder ${{{name}}}")
        return variables[name]

    return PLACEHOLDER.sub(substitute, statement)


def run_statement(client, warehouse_id: str, catalog: str, statement: str, poll_seconds: float = 2.0):
    """Execute one statement and wait for it to finish. Returns the SDK response."""
    response = client.statement_execution.execute_statement(
        warehouse_id=warehouse_id, catalog=catalog, statement=statement, wait_timeout="50s"
    )
    while response.status.state.value not in TERMINAL_STATES:
        time.sleep(poll_seconds)
        response = client.statement_execution.get_statement(response.statement_id)
    if response.status.state.value != "SUCCEEDED":
        error = response.status.error
        detail = f"{error.error_code}: {error.message}" if error else response.status.state.value
        raise SqlError(detail)
    return response


def query_rows(client, warehouse_id: str, catalog: str, statement: str) -> list[list]:
    """Run a SELECT and return its rows (all values come back as strings or None)."""
    response = run_statement(client, warehouse_id, catalog, statement)
    return (response.result.data_array if response.result else None) or []


def run_file(client, warehouse_id: str, catalog: str, path: pathlib.Path, variables: dict[str, str]) -> None:
    statements = split_statements(path.read_text(encoding="utf-8"))
    print(f"== {path} ({len(statements)} statement(s))")
    for number, raw in enumerate(statements, start=1):
        statement = render(raw, variables)
        headline = " ".join(statement.split())[:90]
        started = time.time()
        response = run_statement(client, warehouse_id, catalog, statement)
        rows = (response.result.data_array if response.result else None) or []
        print(f"  [{number}] OK {time.time() - started:.1f}s  {headline}")
        for row in rows[:20]:
            print(f"      {row}")


def find_warehouse(client) -> str:
    warehouses = list(client.warehouses.list())
    if len(warehouses) != 1:
        raise SqlError(f"found {len(warehouses)} warehouses; pass --warehouse-id")
    return warehouses[0].id


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run .sql files on a Databricks SQL warehouse.")
    parser.add_argument("files", nargs="+", type=pathlib.Path)
    parser.add_argument("--catalog", default="workspace", help="catalog name (default workspace)")
    parser.add_argument("--profile", default=os.environ.get("DATABRICKS_CONFIG_PROFILE"))
    parser.add_argument("--warehouse-id", default=None, help="default: the only warehouse")
    parser.add_argument("--set", action="append", default=[], metavar="NAME=VALUE", help="extra ${NAME}")
    return parser


def main(argv: list[str] | None = None) -> int:
    from databricks.sdk import WorkspaceClient  # imported here so tests need no SDK

    args = build_parser().parse_args(argv)
    variables = {"catalog": args.catalog}
    for item in args.set:
        name, _, value = item.partition("=")
        variables[name] = value
    client = WorkspaceClient(profile=args.profile) if args.profile else WorkspaceClient()
    try:
        warehouse_id = args.warehouse_id or find_warehouse(client)
        for path in args.files:
            run_file(client, warehouse_id, args.catalog, path, variables)
    except SqlError as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    exit_code = main()
    if exit_code:
        sys.exit(exit_code)
