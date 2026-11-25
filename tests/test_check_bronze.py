"""Unit tests for scripts/check_bronze.py (the bronze row-count guard). No warehouse needed."""

import check_bronze as cb

MANIFEST = {
    "files": {
        "directory/fips=51/year=2022": {
            "dataset": "directory",
            "file": "ccd/directory/fips=51/year=2022/part.jsonl",
            "rows": 3,
        },
        "directory/fips=51/year=2025": {"dataset": "directory", "file": None, "rows": 0},
        "enrollment/fips=51/year=2022": {
            "dataset": "enrollment",
            "file": "ccd/enrollment/fips=51/year=2022/part.jsonl",
            "rows": 10,
        },
    }
}


def test_relative_file_key_strips_volume_prefix():
    path = "dbfs:/Volumes/workspace/bronze/raw/urban/ccd/directory/fips=51/year=2022/part.jsonl"
    assert cb.relative_file_key(path) == "ccd/directory/fips=51/year=2022/part.jsonl"


def test_relative_file_key_leaves_unknown_paths_alone():
    assert cb.relative_file_key("somewhere/else.jsonl") == "somewhere/else.jsonl"


def test_expected_counts_filters_by_dataset_and_skips_empty_pulls():
    assert cb.expected_counts(MANIFEST, "directory") == {"ccd/directory/fips=51/year=2022/part.jsonl": 3}
    assert cb.expected_counts(MANIFEST, "enrollment") == {"ccd/enrollment/fips=51/year=2022/part.jsonl": 10}


def test_matching_counts_have_no_problems():
    expected = {"a": 3, "b": 5}
    assert cb.compare_counts(expected, {"a": 3, "b": 5}) == []


def test_half_loaded_file_is_reported():
    problems = cb.compare_counts({"a": 100}, {"a": 60})
    assert problems == ["row count differs: a manifest=100 bronze=60"]


def test_missing_file_is_reported():
    problems = cb.compare_counts({"a": 3, "b": 5}, {"a": 3})
    assert len(problems) == 1 and "missing in bronze: b" in problems[0]


def test_unexpected_file_is_reported():
    problems = cb.compare_counts({"a": 3}, {"a": 3, "zzz": 9})
    assert len(problems) == 1 and "in bronze but not in manifest: zzz" in problems[0]


def test_duplicated_load_is_caught_as_count_mismatch():
    # a re-run that appended the same file twice doubles its count
    assert cb.compare_counts({"a": 3}, {"a": 6}) != []
