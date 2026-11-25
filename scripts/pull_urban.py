"""Pull CCD school data from the Urban Institute Education Data API.

Writes one JSON Lines file per dataset, state and year, plus a manifest.json
beside them. The same script runs on a laptop or inside Databricks: only the
--out folder changes (for example /Volumes/workspace/bronze/raw/urban).

Layout under --out:
    ccd/<dataset>/fips=<state>/year=<year>/part.jsonl
    manifest.json

Files are written with sorted rows and sorted keys, so re-running the pull on
unchanged source data produces byte-identical files and identical checksums.
Rows are otherwise left exactly as the API delivered them.

Urban's data is licensed under ODC-By v1.0: credit the Urban Institute
Education Data Portal when you use it.

Usage:
    python scripts/pull_urban.py --states 51 --years 2015-2024
    python scripts/pull_urban.py --years 2022 --datasets directory --dry-run
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
import time
from datetime import datetime, timezone

import requests

BASE_URL = "https://educationdata.urban.org/api/v1"

# Grade codes in Urban's codebook: -1 Pre-K, 0 Kindergarten, 1-15, 99 Total, 999 Not specified.
# Pre-K is spelled "pk" in the URL ("grade--1" returns HTTP 500). Rows still carry grade = -1.
ALL_GRADES = ["pk"] + [str(n) for n in range(0, 16)] + ["99", "999"]

DATASETS = {
    "directory": {
        "path": "schools/ccd/directory/{year}/",
        "grades": [None],
    },
    "enrollment": {
        "path": "schools/ccd/enrollment/{year}/grade-{grade}/",
        "grades": ALL_GRADES,
    },
    "enrollment_race": {
        "path": "schools/ccd/enrollment/{year}/grade-{grade}/race/",
        "grades": ["99"],
    },
}
DEFAULT_DATASETS = ["directory", "enrollment"]

RETRY_STATUSES = {429, 500, 502, 503, 504}


class PullError(Exception):
    """A request failed after retries, or a response did not match the request."""


def parse_years(text: str) -> list[int]:
    """Parse '2015-2024', '2019', or '2015,2018,2020-2022' into a sorted list of years."""
    years: set[int] = set()
    for part in text.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            lo, hi = int(start), int(end)
            if lo > hi:
                raise ValueError(f"year range runs backwards: {part}")
            years.update(range(lo, hi + 1))
        else:
            years.add(int(part))
    if not years:
        raise ValueError("no years given")
    return sorted(years)


def parse_states(text: str) -> list[int]:
    """Parse '51' or '51,24' into state FIPS codes."""
    states = sorted({int(p) for p in text.split(",") if p.strip()})
    if not states:
        raise ValueError("no states given")
    return states


def request_plan(dataset: str, year: int, fips: int) -> list[dict]:
    """The API requests needed for one dataset, state and year (no network)."""
    spec = DATASETS[dataset]
    plan = []
    for grade in spec["grades"]:
        path = spec["path"].format(year=year, grade=grade)
        plan.append({"grade": grade, "url": f"{BASE_URL}/{path}", "params": {"fips": fips}})
    return plan


def output_path(out_dir: pathlib.Path, dataset: str, fips: int, year: int) -> pathlib.Path:
    return out_dir / "ccd" / dataset / f"fips={fips}" / f"year={year}" / "part.jsonl"


def fetch_all(
    session,
    url: str,
    params: dict | None,
    pause: float = 0.5,
    retries: int = 4,
    backoff: float = 1.0,
    sleep=time.sleep,
) -> tuple[list[dict], list[str]]:
    """Follow the API's `next` links until every page is read.

    Returns (rows, page_urls). Retries on connection errors and on 429/5xx
    responses with exponential backoff; raises PullError when retries run out.
    """
    rows: list[dict] = []
    pages: list[str] = []
    next_url, next_params = url, params
    while next_url:
        body = _get_json(session, next_url, next_params, retries, backoff, sleep)
        pages.append(next_url)
        rows.extend(body.get("results") or [])
        next_url, next_params = body.get("next"), None  # `next` already carries the query
        if next_url:
            sleep(pause)
    return rows, pages


def _get_json(session, url, params, retries, backoff, sleep) -> dict:
    last_problem = "unknown"
    for attempt in range(retries + 1):
        try:
            response = session.get(url, params=params, timeout=60)
        except requests.RequestException as exc:
            last_problem = f"{type(exc).__name__}: {exc}"
        else:
            if response.status_code == 200:
                try:
                    return response.json()
                except ValueError:
                    last_problem = "HTTP 200 but the body was not JSON"
            elif response.status_code in RETRY_STATUSES:
                last_problem = f"HTTP {response.status_code}"
            else:
                raise PullError(f"{url}: HTTP {response.status_code} (not retried)")
        if attempt < retries:
            sleep(backoff * (2**attempt))
    raise PullError(f"{url}: gave up after {retries + 1} attempts ({last_problem})")


def validate_rows(rows: list[dict], fips: int, year: int) -> None:
    """Fail loudly if the API returned rows for another state or year."""
    for row in rows:
        if int(row["fips"]) != fips:
            raise PullError(f"row for state {row['fips']} in a pull for state {fips}")
        if int(row["year"]) != year:
            raise PullError(f"row for year {row['year']} in a pull for year {year}")


def serialize_rows(rows: list[dict]) -> bytes:
    """Deterministic JSON Lines: sorted keys, sorted rows, LF line endings, UTF-8."""
    lines = sorted(json.dumps(row, sort_keys=True, ensure_ascii=False) for row in rows)
    return ("".join(line + "\n" for line in lines)).encode("utf-8")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_manifest(path: pathlib.Path) -> dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"source": BASE_URL, "generated_by": "scripts/pull_urban.py", "files": {}}


def save_manifest(path: pathlib.Path, manifest: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    path.write_bytes(text.encode("utf-8"))


def pull_one(
    session,
    out_dir: pathlib.Path,
    dataset: str,
    fips: int,
    year: int,
    pause: float = 0.5,
    sleep=time.sleep,
    retries: int = 4,
    backoff: float = 1.0,
) -> tuple[str, dict]:
    """Pull one dataset, state and year. Returns (status, manifest_entry).

    status is 'written', 'unchanged' (same bytes already on disk) or 'empty'
    (the API returned zero rows, so no file is written).
    """
    all_rows: list[dict] = []
    requests_made: list[dict] = []
    for step in request_plan(dataset, year, fips):
        rows, pages = fetch_all(session, step["url"], step["params"], pause, retries, backoff, sleep)
        validate_rows(rows, fips, year)
        all_rows.extend(rows)
        requests_made.append(
            {"grade": step["grade"], "url": pages[0], "pages": len(pages), "rows": len(rows)}
        )
        sleep(pause)

    entry = {
        "dataset": dataset,
        "fips": fips,
        "year": year,
        "fetched_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "rows": len(all_rows),
        "requests": requests_made,
        "file": None,
        "bytes": 0,
        "sha256": None,
    }
    if not all_rows:
        return "empty", entry

    data = serialize_rows(all_rows)
    path = output_path(out_dir, dataset, fips, year)
    entry["file"] = path.relative_to(out_dir).as_posix()
    entry["bytes"] = len(data)
    entry["sha256"] = sha256_hex(data)
    if path.exists() and sha256_hex(path.read_bytes()) == entry["sha256"]:
        return "unchanged", entry
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return "written", entry


def manifest_key(entry: dict) -> str:
    return f"{entry['dataset']}/fips={entry['fips']}/year={entry['year']}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Pull CCD data from the Urban Institute API.")
    parser.add_argument("--states", default="51", help="state FIPS codes, e.g. 51 or 51,24 (default 51)")
    parser.add_argument(
        "--years", default="2015-2024", help="e.g. 2015-2024 or 2019,2022 (default 2015-2024)"
    )
    parser.add_argument(
        "--datasets",
        default=",".join(DEFAULT_DATASETS),
        help=f"comma list from: {', '.join(DATASETS)} (default {','.join(DEFAULT_DATASETS)})",
    )
    parser.add_argument("--out", default="raw/urban", help="output folder (default raw/urban)")
    parser.add_argument("--pause", type=float, default=0.5, help="seconds between requests (default 0.5)")
    parser.add_argument("--dry-run", action="store_true", help="print the requests and exit")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    states = parse_states(args.states)
    years = parse_years(args.years)
    datasets = [d.strip() for d in args.datasets.split(",") if d.strip()]
    unknown = [d for d in datasets if d not in DATASETS]
    if unknown:
        print(f"unknown dataset(s): {unknown}. Choose from {list(DATASETS)}", file=sys.stderr)
        return 2
    out_dir = pathlib.Path(args.out)

    if args.dry_run:
        total = 0
        for fips in states:
            for dataset in datasets:
                for year in years:
                    plan = request_plan(dataset, year, fips)
                    total += len(plan)
                    first = f"{plan[0]['url']}?fips={fips}"
                    print(f"{dataset} fips={fips} year={year}: {len(plan)} request(s), first: {first}")
        print(f"total requests (before pagination): {total}")
        return 0

    session = requests.Session()
    manifest_path = out_dir / "manifest.json"
    manifest = load_manifest(manifest_path)
    failures: list[str] = []
    for fips in states:
        for dataset in datasets:
            for year in years:
                label = f"{dataset} fips={fips} year={year}"
                try:
                    status, entry = pull_one(session, out_dir, dataset, fips, year, pause=args.pause)
                except PullError as exc:
                    failures.append(f"{label}: {exc}")
                    print(f"FAILED   {label}: {exc}")
                    continue
                manifest["files"][manifest_key(entry)] = entry
                save_manifest(manifest_path, manifest)  # save as we go so a crash keeps progress
                print(f"{status:10} {label}: {entry['rows']} rows")
    if failures:
        print(f"\n{len(failures)} pull(s) failed:", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
