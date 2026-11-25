"""Unit tests for scripts/check_gold.py (pure arithmetic only)."""

import check_gold as cg


def test_percent_gap():
    assert cg.percent_gap(1000, 999) == 0.1
    assert cg.percent_gap(1000, 1000) == 0.0


def test_percent_gap_with_empty_state_total_is_zero():
    assert cg.percent_gap(0, 0) == 0.0


def test_gap_within_limit_is_fine():
    assert cg.gap_problems([(2024, 1257315, 1257250)]) == []


def test_gap_over_limit_is_reported_with_year():
    problems = cg.gap_problems([(2015, 1283548, 1283451), (2016, 1000000, 990000)])
    assert len(problems) == 1 and problems[0].startswith("2016:")


def test_division_total_above_state_total_is_reported():
    # divisions are a subset of the state, so a larger sum means a double count
    problems = cg.gap_problems([(2020, 1000, 1005)])
    assert len(problems) == 1


def test_every_gold_table_has_a_key():
    assert len(cg.KEYS) == 6
    assert all(cols for cols in cg.KEYS.values())
