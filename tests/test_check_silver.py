"""Unit tests for scripts/check_silver.py (the bronze = silver + quarantine arithmetic)."""

import check_silver as cs


def test_balanced_counts_have_no_problem():
    assert cs.balance_problem(100, 97, 3) is None


def test_missing_rows_are_reported_with_the_gap():
    message = cs.balance_problem(100, 90, 3)
    assert "7 rows unaccounted for" in message and "-" not in message.split(";")[1]


def test_extra_rows_are_reported_as_negative_gap():
    message = cs.balance_problem(100, 99, 5)
    assert "-4 rows unaccounted for" in message


def test_zero_quarantine_is_fine_when_everything_is_silver():
    assert cs.balance_problem(10, 10, 0) is None


def test_every_bronze_table_has_a_balance_rule_and_key_check():
    assert set(cs.BALANCES) == {
        "bronze.ccd_directory",
        "bronze.ccd_district_directory",
        "bronze.ccd_enrollment",
    }
    silver_tables = {t for silvers, _ in cs.BALANCES.values() for t in silvers}
    assert silver_tables == set(cs.KEYS)
