"""Integration test: run the REAL silver SQL against scratch schemas holding deliberately bad rows.

The real Virginia data is clean, so its quarantine is empty. This test proves each cleaning rule fires.
It needs a Databricks warehouse, so it is skipped unless RUN_WAREHOUSE_TESTS=1. Run:
    RUN_WAREHOUSE_TESTS=1 DATABRICKS_CONFIG_PROFILE=<profile> python -m pytest tests/integration -q
It creates and then drops the schemas test_bronze and test_silver.
The real bronze and silver are never touched.
"""

import os
import pathlib
import re

import pytest

import run_sql

pytestmark = pytest.mark.skipif(
    not os.environ.get("RUN_WAREHOUSE_TESTS"),
    reason="needs a Databricks warehouse (set RUN_WAREHOUSE_TESTS=1)",
)

CATALOG = os.environ.get("TEST_CATALOG", "workspace")
SQL_DIR = pathlib.Path(__file__).resolve().parents[2] / "sql" / "silver"
SILVER_FILES = [
    "005_quarantine.sql",
    "010_dimensions.sql",
    "020_district_year.sql",
    "030_school_year.sql",
    "040_enrollment.sql",
]
T_NEW, T_OLD = "2026-01-02 00:00:00", "2026-01-01 00:00:00"


@pytest.fixture(scope="module")
def warehouse():
    from databricks.sdk import WorkspaceClient

    profile = os.environ.get("DATABRICKS_CONFIG_PROFILE")
    client = WorkspaceClient(profile=profile) if profile else WorkspaceClient()
    return client, run_sql.find_warehouse(client)


def run(warehouse, sql):
    client, warehouse_id = warehouse
    return run_sql.run_statement(client, warehouse_id, CATALOG, sql)


def rows(warehouse, sql):
    client, warehouse_id = warehouse
    return run_sql.query_rows(client, warehouse_id, CATALOG, sql)


def redirect(sql: str) -> str:
    """Point the silver SQL at the scratch schemas (word-boundary match leaves test_* names alone)."""
    sql = re.sub(r"\bbronze\.", "test_bronze.", sql)
    return re.sub(r"\bsilver\.", "test_silver.", sql)


def insert(warehouse, table, columns, values):
    cols = ", ".join(columns)

    def lit(v):
        return "NULL" if v is None else "'" + v.replace("'", "''") + "'"

    tuples = ",\n".join("(" + ", ".join(lit(v) for v in row) + ")" for row in values)
    run(warehouse, f"INSERT INTO test_bronze.{table} ({cols}) VALUES {tuples}")


@pytest.fixture(scope="module")
def built(warehouse):
    for schema in ("test_bronze", "test_silver"):
        run(warehouse, f"DROP SCHEMA IF EXISTS {schema} CASCADE")
        run(warehouse, f"CREATE SCHEMA {schema}")
    try:
        for table in ("ccd_directory", "ccd_district_directory", "ccd_enrollment"):
            run(warehouse, f"CREATE TABLE test_bronze.{table} AS SELECT * FROM bronze.{table} WHERE 1 = 0")

        # (ncessch, leaid, year, fips, grade, race, sex, enrollment, file, ingested_at)
        enrollment_cols = [
            "ncessch",
            "leaid",
            "year",
            "fips",
            "grade",
            "race",
            "sex",
            "enrollment",
            "_source_file",
        ]
        ok = ("510000000001", "5100001", "2022", "51")

        def e(n=ok[0], leaid=ok[1], year=ok[2], fips=ok[3], grade="3", race="99", sex="99", enr="10", f="f1"):
            return (n, leaid, year, fips, grade, race, sex, enr, f)

        good = [
            e(),  # E1: kept
            e(grade="4", enr="-1"),  # status missing
            e(grade="5", enr="-2"),  # status not_applicable
            e(grade="6", enr="-3"),  # status suppressed
            e(grade="7", enr=None),  # null -> status missing
            e(grade="99", enr="500"),  # the total row -> enrollment_total
            e(n="10000000001", leaid="100001", fips="1"),  # 11-digit ID: left-padded to 12, state 1 kept
        ]
        bad = [
            e(n=None),  # missing_key
            e(year="1999"),  # bad_year
            e(n="ABC"),  # bad_id_format
            e(n="240000000001", leaid="2400001"),  # state_mismatch (ID says 24, fips says 51)
            e(grade="77"),  # unknown_grade
            e(race="1"),  # unexpected_breakdown
            e(enr="abc"),  # bad_enrollment_value
            e(enr="-9"),  # unknown_special_value
        ]
        insert(
            warehouse, "ccd_enrollment", [*enrollment_cols, "_ingested_at"], [(*r, T_NEW) for r in good + bad]
        )
        insert(
            warehouse, "ccd_enrollment", [*enrollment_cols, "_ingested_at"], [(*e(enr="99", f="f0"), T_OLD)]
        )
        # duplicate of E1 (older ingest) -> duplicate_loser; the newer value 10 must win

        directory_cols = [
            "ncessch", "leaid", "year", "fips", "school_status", "school_level", "charter", "enrollment",
            "_source_file",
        ]  # fmt: skip
        d_good = ("510000000001", "5100001", "2022", "51", "1", "1", "1", "-1", "f1")
        insert(warehouse, "ccd_directory", [*directory_cols, "_ingested_at"], [(*d_good, T_NEW)])
        insert(warehouse, "ccd_directory", [*directory_cols, "_ingested_at"], [(*d_good[:-1], "f0", T_OLD)])
        insert(
            warehouse,
            "ccd_directory",
            [*directory_cols, "_ingested_at"],
            [("510000000002", "5100001", "1999", "51", "1", "1", "0", "5", "f1", T_NEW)],
        )

        district_cols = ["leaid", "year", "fips", "agency_type", "_source_file"]
        insert(
            warehouse,
            "ccd_district_directory",
            [*district_cols, "_ingested_at"],
            [
                ("5100001", "2015", "51", "3", "f1", T_NEW),  # supervisory union in 2015
                ("5100001", "2016", "51", "3", "f1", T_NEW),
                ("5100001", "2017", "51", "1", "f1", T_NEW),  # regular division from 2017
                ("5100002", "2017", "51", "4", "f1", T_NEW),  # regional agency, never a division
                ("2400001", "2017", "51", "1", "f1", T_NEW),  # state_mismatch
            ],
        )

        client, warehouse_id = warehouse
        for name in SILVER_FILES:
            for statement in run_sql.split_statements((SQL_DIR / name).read_text(encoding="utf-8")):
                run_sql.run_statement(client, warehouse_id, CATALOG, redirect(statement))
        yield warehouse
    finally:
        for schema in ("test_bronze", "test_silver"):
            run(warehouse, f"DROP SCHEMA IF EXISTS {schema} CASCADE")


def quarantine_counts(warehouse):
    result = rows(
        warehouse,
        "SELECT source_table, reason, COUNT(*) FROM test_silver.quarantine GROUP BY 1, 2",
    )
    return {(s.split(".")[-1], r): int(c) for s, r, c in result}


def test_enrollment_rows_land_in_quarantine_with_the_right_reason(built):
    counts = quarantine_counts(built)
    for reason in (
        "missing_key",
        "bad_year",
        "bad_id_format",
        "state_mismatch",
        "unknown_grade",
        "unexpected_breakdown",
        "bad_enrollment_value",
        "unknown_special_value",
        "duplicate_loser",
    ):
        assert counts.get(("ccd_enrollment", reason)) == 1, reason


def test_enrollment_balance_bronze_equals_silver_plus_quarantine(built):
    bronze = int(rows(built, "SELECT COUNT(*) FROM test_bronze.ccd_enrollment")[0][0])
    silver = int(rows(built, "SELECT COUNT(*) FROM test_silver.enrollment")[0][0])
    total = int(rows(built, "SELECT COUNT(*) FROM test_silver.enrollment_total")[0][0])
    quarantined = sum(v for (t, _), v in quarantine_counts(built).items() if t == "ccd_enrollment")
    assert bronze == silver + total + quarantined == 16


def test_latest_ingested_duplicate_wins(built):
    result = rows(
        built, "SELECT enrollment FROM test_silver.enrollment WHERE ncessch='510000000001' AND grade_code=3"
    )
    assert result == [["10"]]


def test_special_values_become_null_with_a_status(built):
    result = rows(
        built,
        "SELECT grade_code, enrollment, enrollment_status FROM test_silver.enrollment "
        "WHERE ncessch='510000000001' AND grade_code IN (4,5,6,7) ORDER BY grade_code",
    )
    assert result == [
        ["4", None, "missing"],
        ["5", None, "not_applicable"],
        ["6", None, "suppressed"],
        ["7", None, "missing"],
    ]


def test_total_row_is_kept_apart_from_the_grades(built):
    total = rows(
        built, "SELECT total_enrollment FROM test_silver.enrollment_total WHERE ncessch='510000000001'"
    )
    assert total == [["500"]]
    grade_99 = rows(built, "SELECT COUNT(*) FROM test_silver.enrollment WHERE grade_code = 99")
    assert grade_99 == [["0"]]


def test_short_ids_are_left_padded(built):
    result = rows(built, "SELECT ncessch, leaid FROM test_silver.enrollment WHERE state_fips = 1")
    assert result == [["010000000001", "0100001"]]


def test_directory_decodes_and_quarantines(built):
    counts = quarantine_counts(built)
    assert counts[("ccd_directory", "duplicate_loser")] == 1
    assert counts[("ccd_directory", "bad_year")] == 1
    result = rows(
        built,
        "SELECT school_level, school_status, is_charter, directory_enrollment, state_name "
        "FROM test_silver.school_year",
    )
    assert result == [["Primary", "Open", "true", None, "Virginia"]]


def test_division_flag_uses_any_year_not_each_year(built):
    result = rows(
        built, "SELECT leaid, year, is_school_division FROM test_silver.district_year ORDER BY 1, 2"
    )
    assert result == [
        ["5100001", "2015", "true"],  # was a supervisory union in 2015, still a division
        ["5100001", "2016", "true"],
        ["5100001", "2017", "true"],
        ["5100002", "2017", "false"],
    ]
    assert quarantine_counts(built)[("ccd_district_directory", "state_mismatch")] == 1
