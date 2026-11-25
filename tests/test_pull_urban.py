"""Unit tests for scripts/pull_urban.py. No network: HTTP is replaced by a fake session."""

import json

import pytest
import requests

import pull_urban as pu


class FakeResponse:
    def __init__(self, status_code=200, body=None, json_error=False):
        self.status_code = status_code
        self._body = body if body is not None else {}
        self._json_error = json_error

    def json(self):
        if self._json_error:
            raise ValueError("not json")
        return self._body


class FakeSession:
    """Returns queued responses (or raises queued exceptions) in order and records calls."""

    def __init__(self, queue):
        self.queue = list(queue)
        self.calls = []

    def get(self, url, params=None, timeout=None):
        self.calls.append((url, params))
        item = self.queue.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def no_sleep(_seconds):
    pass


def page(results, next_url=None):
    return FakeResponse(200, {"count": len(results), "next": next_url, "previous": None, "results": results})


def row(ncessch="510003802280", year=2022, fips=51, **extra):
    return {"ncessch": ncessch, "year": year, "fips": fips, **extra}


# --- parsing and planning -------------------------------------------------------------------


def test_parse_years_range_list_and_mixed():
    assert pu.parse_years("2015-2017") == [2015, 2016, 2017]
    assert pu.parse_years("2019") == [2019]
    assert pu.parse_years("2022, 2015,2018-2019") == [2015, 2018, 2019, 2022]


def test_parse_years_rejects_backwards_and_empty():
    with pytest.raises(ValueError):
        pu.parse_years("2024-2015")
    with pytest.raises(ValueError):
        pu.parse_years(" , ")


def test_parse_states_dedupes_and_sorts():
    assert pu.parse_states("51,24,51") == [24, 51]


def test_request_plan_directory_is_one_request():
    plan = pu.request_plan("directory", 2022, 51)
    assert len(plan) == 1
    assert plan[0]["url"] == f"{pu.BASE_URL}/schools/ccd/directory/2022/"
    assert plan[0]["params"] == {"fips": 51}


def test_request_plan_enrollment_covers_every_codebook_grade():
    plan = pu.request_plan("enrollment", 2022, 51)
    urls = [step["url"] for step in plan]
    assert f"{pu.BASE_URL}/schools/ccd/enrollment/2022/grade-pk/" in urls  # Pre-K is spelled "pk"
    assert f"{pu.BASE_URL}/schools/ccd/enrollment/2022/grade-0/" in urls  # kindergarten
    assert f"{pu.BASE_URL}/schools/ccd/enrollment/2022/grade-99/" in urls  # total row
    assert f"{pu.BASE_URL}/schools/ccd/enrollment/2022/grade-999/" in urls
    assert not any("grade--1" in u for u in urls)  # the API returns HTTP 500 for that spelling
    assert len(urls) == len(set(urls)) == 19  # pk, 0-15, 99, 999


def test_request_plan_district_directory_is_one_request():
    plan = pu.request_plan("district_directory", 2024, 51)
    assert [s["url"] for s in plan] == [f"{pu.BASE_URL}/school-districts/ccd/directory/2024/"]


def test_request_plan_race_pulls_total_grade_only():
    plan = pu.request_plan("enrollment_race", 2023, 51)
    assert [s["url"] for s in plan] == [f"{pu.BASE_URL}/schools/ccd/enrollment/2023/grade-99/race/"]


def test_output_path_layout(tmp_path):
    path = pu.output_path(tmp_path, "directory", 51, 2019)
    assert path.relative_to(tmp_path).as_posix() == "ccd/directory/fips=51/year=2019/part.jsonl"


# --- fetching ------------------------------------------------------------------------------


def test_fetch_all_follows_next_and_sends_params_only_once():
    session = FakeSession([page([row(ncessch="a")], "https://x/api?page=2"), page([row(ncessch="b")])])
    rows, pages = pu.fetch_all(session, "https://x/api", {"fips": 51}, sleep=no_sleep)
    assert [r["ncessch"] for r in rows] == ["a", "b"]
    assert pages == ["https://x/api", "https://x/api?page=2"]
    assert session.calls == [("https://x/api", {"fips": 51}), ("https://x/api?page=2", None)]


def test_fetch_all_retries_server_errors_then_succeeds():
    session = FakeSession([FakeResponse(500), requests.ConnectionError("boom"), page([row()])])
    sleeps = []
    rows, _ = pu.fetch_all(session, "https://x/api", {"fips": 51}, sleep=sleeps.append, backoff=1.0)
    assert len(rows) == 1
    assert sleeps == [1.0, 2.0]  # exponential backoff


def test_fetch_all_gives_up_after_retries():
    session = FakeSession([FakeResponse(500)] * 3)
    with pytest.raises(pu.PullError, match="gave up after 3 attempts"):
        pu.fetch_all(session, "https://x/api", None, retries=2, sleep=no_sleep)


def test_fetch_all_does_not_retry_client_errors():
    session = FakeSession([FakeResponse(404)])
    with pytest.raises(pu.PullError, match="HTTP 404"):
        pu.fetch_all(session, "https://x/api", None, sleep=no_sleep)
    assert len(session.calls) == 1


def test_fetch_all_treats_non_json_200_as_retryable():
    session = FakeSession([FakeResponse(200, json_error=True), page([row()])])
    rows, _ = pu.fetch_all(session, "https://x/api", None, sleep=no_sleep)
    assert len(rows) == 1


# --- validation and serialization ------------------------------------------------------------


def test_validate_rows_accepts_matching_state_and_year():
    pu.validate_rows([row(year=2022, fips=51)], fips=51, year=2022)


def test_validate_rows_rejects_other_state_or_year():
    with pytest.raises(pu.PullError, match="state 24"):
        pu.validate_rows([row(fips=24)], fips=51, year=2022)
    with pytest.raises(pu.PullError, match="year 2021"):
        pu.validate_rows([row(year=2021)], fips=51, year=2022)


def test_serialize_rows_is_order_independent_and_lf_only():
    a = {"b": 1, "a": 2}
    b = {"a": 3, "b": 4}
    one = pu.serialize_rows([a, b])
    two = pu.serialize_rows([{"a": 3, "b": 4}, {"a": 2, "b": 1}])
    assert one == two
    assert b"\r" not in one
    assert one.endswith(b"\n")


def test_serialize_rows_keeps_values_untouched():
    rows = [{"ncessch": "010000000001", "enrollment": None, "name": "Café School"}]
    line = pu.serialize_rows(rows).decode("utf-8").strip()
    parsed = json.loads(line)
    assert parsed == rows[0]  # leading zero kept, null kept, accents kept


# --- pull_one: files, manifest entry, idempotence ----------------------------------------------


def two_page_directory_session():
    return FakeSession([page([row(ncessch="b")], "https://x/next"), page([row(ncessch="a")])])


def test_pull_one_writes_file_and_manifest_entry(tmp_path):
    status, entry = pu.pull_one(two_page_directory_session(), tmp_path, "directory", 51, 2022, sleep=no_sleep)
    assert status == "written"
    path = tmp_path / entry["file"]
    assert path.exists()
    assert entry["rows"] == 2
    assert entry["bytes"] == path.stat().st_size
    assert entry["sha256"] == pu.sha256_hex(path.read_bytes())
    assert entry["requests"][0]["pages"] == 2
    assert pu.manifest_key(entry) == "directory/fips=51/year=2022"


def test_pull_one_second_run_is_unchanged_with_same_checksum(tmp_path):
    pull = pu.pull_one
    _, first = pull(two_page_directory_session(), tmp_path, "directory", 51, 2022, sleep=no_sleep)
    status, second = pull(two_page_directory_session(), tmp_path, "directory", 51, 2022, sleep=no_sleep)
    assert status == "unchanged"
    assert second["sha256"] == first["sha256"]


def test_pull_one_empty_result_writes_no_file(tmp_path):
    status, entry = pu.pull_one(FakeSession([page([])]), tmp_path, "directory", 51, 2025, sleep=no_sleep)
    assert status == "empty"
    assert entry["rows"] == 0
    assert entry["file"] is None
    assert not (tmp_path / "ccd").exists()


def test_pull_one_enrollment_combines_all_grades_into_one_file(tmp_path):
    responses = [page([row(grade=i)]) for i in range(19)]
    status, entry = pu.pull_one(FakeSession(responses), tmp_path, "enrollment", 51, 2022, sleep=no_sleep)
    assert status == "written"
    assert entry["rows"] == 19
    assert len(entry["requests"]) == 19
    lines = (tmp_path / entry["file"]).read_text(encoding="utf-8").splitlines()
    assert len(lines) == 19


def test_pull_one_rejects_wrong_state_and_writes_nothing(tmp_path):
    session = FakeSession([page([row(fips=24)])])
    with pytest.raises(pu.PullError):
        pu.pull_one(session, tmp_path, "directory", 51, 2022, sleep=no_sleep)
    assert not (tmp_path / "ccd").exists()


# --- manifest and CLI ----------------------------------------------------------------------


def test_manifest_round_trip_and_default(tmp_path):
    path = tmp_path / "manifest.json"
    assert pu.load_manifest(path)["files"] == {}
    manifest = pu.load_manifest(path)
    manifest["files"]["k"] = {"rows": 1}
    pu.save_manifest(path, manifest)
    assert pu.load_manifest(path)["files"] == {"k": {"rows": 1}}


def test_main_dry_run_makes_no_requests_and_writes_nothing(tmp_path, capsys):
    code = pu.main(["--years", "2022", "--out", str(tmp_path / "out"), "--dry-run"])
    assert code == 0
    assert "total requests (before pagination): 21" in capsys.readouterr().out  # 1 + 1 + 19 grades
    assert not (tmp_path / "out").exists()


def test_main_rejects_unknown_dataset(capsys):
    assert pu.main(["--datasets", "nope", "--dry-run"]) == 2
