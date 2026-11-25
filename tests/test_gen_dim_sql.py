"""Unit tests for scripts/gen_dim_sql.py (pure parsing and SQL generation)."""

import gen_dim_sql as g
import run_sql


def test_clean_label_strips_code_prefix():
    assert g.clean_label("11 - City, large") == "City, large"
    assert g.clean_label("-1 - Missing/not reported") == "Missing/not reported"
    assert g.clean_label("0 - Kindergarten") == "Kindergarten"


def test_clean_label_unescapes_html():
    assert g.clean_label("5 - Rural &amp; remote") == "Rural & remote"


def test_clean_label_keeps_later_dashes():
    assert g.clean_label("7 - Rural, outside CBSA - north") == "Rural, outside CBSA - north"


def test_parse_values_reads_codebook_dict_string():
    text = "{-1: '-1 - Pre-K', 0: '0 - Kindergarten', 1: '1 - 1', 99: '99 - Total'}"
    assert g.parse_values(text) == {-1: "Pre-K", 0: "Kindergarten", 1: "1", 99: "Total"}


def test_grade_label_makes_numbers_readable_but_leaves_words():
    assert g.grade_label(3, "3") == "Grade 3"
    assert g.grade_label(99, "Total") == "Total"
    assert g.grade_label(0, "Kindergarten") == "Kindergarten"


def test_sql_literal_doubles_quotes():
    assert g.sql_literal("Governor's") == "'Governor''s'"


def test_build_dimension_sql_shape():
    sql = g.build_dimension_sql("dim_x", "x", "A test dimension.", {2: "Two", -1: "Missing"})
    assert sql.startswith("CREATE OR REPLACE TABLE silver.dim_x")
    assert sql.index("(-1, 'Missing')") < sql.index("(2, 'Two')")  # sorted by code
    assert "AS t(code, label);" in sql


def test_generated_file_is_one_statement_per_dimension_and_parses():
    codebook = {
        "results": [
            {"variable": v, "values": "{1: '1 - One', -1: '-1 - Missing/not reported'}"}
            for v, _ in g.DIMENSIONS.values()
        ]
    }
    text = g.build_file(codebook)
    statements = run_sql.split_statements(text)
    assert len(statements) == len(g.DIMENSIONS)
    assert all(s.startswith("CREATE OR REPLACE TABLE silver.dim_") for s in statements)
