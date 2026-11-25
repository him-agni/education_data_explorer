"""Unit tests for eval/validate_questions.py (structure rules, no warehouse)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "eval"))

import validate_questions as vq  # noqa: E402


def row(
    i, group="g01", split="dev", category="lookup", expected="answer", sql="SELECT 1 FROM gold.x", q="Q?"
):
    return {
        "id": f"q{i:03d}",
        "question": q,
        "group": group,
        "category": category,
        "split": split,
        "gold_sql": sql,
        "expected": expected,
    }


def good_set():
    rows = []
    n = 0
    for g in range(10):  # 10 answerable groups x 3 phrasings = 30 rows; 3 groups in test
        split = "test" if g < 4 else "dev"
        for _ in range(3):
            n += 1
            rows.append(row(n, group=f"g{g:02d}", split=split, sql=f"SELECT {g} FROM gold.t"))
    return rows


def test_a_good_set_has_no_problems():
    assert vq.validate_rows(good_set()) == []


def test_the_committed_question_file_is_valid():
    path = pathlib.Path(__file__).resolve().parents[1] / "eval" / "questions.csv"
    assert vq.validate_rows(vq.load_rows(path)) == []


def test_duplicate_ids_are_reported():
    rows = good_set()
    rows[1]["id"] = rows[0]["id"]
    assert any("duplicate id" in p for p in vq.validate_rows(rows))


def test_unknown_category_split_and_expected_are_reported():
    rows = good_set()
    rows[0]["category"] = "weird"
    rows[1]["split"] = "holdout"
    rows[2]["expected"] = "maybe"
    text = " ".join(vq.validate_rows(rows))
    assert "unknown category" in text and "unknown split" in text and "unknown expected" in text


def test_answer_without_sql_and_decline_with_sql_are_reported():
    rows = good_set()
    rows[0]["gold_sql"] = ""
    rows.append(row(99, group="g90", expected="decline", sql="SELECT 1 FROM gold.t"))
    text = " ".join(vq.validate_rows(rows))
    assert "needs a gold_sql" in text and "must have an empty gold_sql" in text


def test_gold_sql_must_use_gold_tables_only():
    rows = good_set()
    for r in rows:
        if r["group"] == "g00":
            r["gold_sql"] = "SELECT * FROM silver.enrollment"
    assert any("gold tables only" in p for p in vq.validate_rows(rows))


def test_gold_sql_must_be_a_single_select():
    rows = good_set()
    for r in rows:
        if r["group"] == "g00":
            r["gold_sql"] = "DROP TABLE gold.x"
    assert any("must be a SELECT" in p for p in vq.validate_rows(rows))
    for r in rows:
        if r["group"] == "g00":
            r["gold_sql"] = "SELECT 1 FROM gold.x; SELECT 2 FROM gold.x"
    assert any("one statement" in p for p in vq.validate_rows(rows))


def test_phrasings_of_a_group_must_share_a_split():
    rows = good_set()
    rows[0]["split"] = (
        "test" if rows[0]["split"] == "dev" else "dev"
    )  # one phrasing leaks into the other split
    assert any("disagree on split" in p for p in vq.validate_rows(rows))


def test_too_few_rows_and_bad_test_share_are_reported():
    assert any("only 3 rows" in p for p in vq.validate_rows(good_set()[:3]))
    rows = good_set()
    for r in rows:
        r["split"] = "dev"
    assert any("test split is 0%" in p for p in vq.validate_rows(rows))


def test_distinct_gold_sql_has_one_entry_per_group():
    rows = good_set() + [row(98, group="g91", expected="decline", sql="")]
    sql = vq.distinct_gold_sql(rows)
    assert len(sql) == 10 and "g91" not in sql
