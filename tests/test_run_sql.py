"""Unit tests for scripts/run_sql.py (pure functions only, no warehouse)."""

import pytest

import run_sql as rs


def test_split_on_semicolons_and_drop_empty():
    assert rs.split_statements("SELECT 1; SELECT 2;;  ") == ["SELECT 1", "SELECT 2"]


def test_split_keeps_semicolon_inside_string():
    text = "COMMENT ON TABLE t IS 'raw; as delivered'; SELECT 1"
    assert rs.split_statements(text) == ["COMMENT ON TABLE t IS 'raw; as delivered'", "SELECT 1"]


def test_split_handles_escaped_quote_inside_string():
    text = "SELECT 'it''s; fine'; SELECT 2"
    assert rs.split_statements(text) == ["SELECT 'it''s; fine'", "SELECT 2"]


def test_split_handles_backtick_identifiers():
    assert rs.split_statements("SELECT `a;b` FROM t; SELECT 2") == ["SELECT `a;b` FROM t", "SELECT 2"]


def test_split_drops_line_and_block_comments():
    text = "-- header; with semicolon\nSELECT 1 /* inline; comment */; -- trailing\nSELECT 2"
    out = rs.split_statements(text)
    assert [" ".join(s.split()) for s in out] == ["SELECT 1", "SELECT 2"]


def test_split_does_not_treat_dashes_in_strings_as_comments():
    assert rs.split_statements("SELECT '--not a comment'; SELECT 2") == [
        "SELECT '--not a comment'",
        "SELECT 2",
    ]


def test_split_multiline_statement_stays_whole():
    text = "COPY INTO t\nFROM (SELECT * FROM 'a')\nFILEFORMAT = JSON;"
    assert len(rs.split_statements(text)) == 1


def test_render_substitutes_placeholders():
    out = rs.render("FROM '/Volumes/${catalog}/bronze/${name}'", {"catalog": "workspace", "name": "raw"})
    assert out == "FROM '/Volumes/workspace/bronze/raw'"


def test_render_missing_placeholder_is_an_error():
    with pytest.raises(rs.SqlError, match="no value for placeholder"):
        rs.render("SELECT '${nope}'", {"catalog": "workspace"})


def test_render_leaves_other_dollars_alone():
    assert rs.render("SELECT '$5 and $x'", {}) == "SELECT '$5 and $x'"
