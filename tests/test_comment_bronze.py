"""Unit tests for scripts/comment_bronze.py (pure comment building)."""

import json

import comment_bronze as cb

LABELS = {"enrollment": "Student enrollment", "year": "Academic year (fall semester)"}


def test_clean_text_removes_html_entities_and_odd_characters():
    assert cb.clean_text("Personnel&mdash;teachers <br/>only") == "Personnel—teachers only"
    assert cb.clean_text("math�science") == "math-science"


def test_build_comment_uses_codebook_label_and_raw_wording():
    text = cb.build_comment("enrollment", LABELS, "2026-11-25")
    assert text == "Student enrollment. Raw string, as delivered by Urban Institute, pulled on 2026-11-25."


def test_build_comment_handles_label_ending_in_period():
    text = cb.build_comment("x", {"x": "Some label."}, "2026-11-25")
    assert text.startswith("Some label. Raw string")


def test_build_comment_for_lineage_columns():
    assert cb.build_comment("_source_file", LABELS, "2026-11-25").startswith("Lineage:")
    assert "loaded into bronze" in cb.build_comment("_ingested_at", LABELS, "2026-11-25")


def test_build_comment_for_unknown_column_says_so():
    text = cb.build_comment("mystery", LABELS, "2026-11-25")
    assert text.startswith("No label in the Urban codebook.")


def test_sql_literal_doubles_quotes():
    assert cb.sql_literal("it's") == "'it''s'"


def test_comment_statement_quotes_identifier_and_text():
    sql = cb.comment_statement("bronze.t", "year", "It's raw")
    assert sql == "ALTER TABLE bronze.t ALTER COLUMN `year` COMMENT 'It''s raw'"


def test_load_labels_reads_results_and_cleans(tmp_path):
    path = tmp_path / "vars.json"
    path.write_text(
        json.dumps({"results": [{"variable": "a", "label": "A&mdash;b"}, {"variable": "b", "label": None}]}),
        encoding="utf-8",
    )
    assert cb.load_labels(path) == {"a": "A—b"}
