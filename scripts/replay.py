"""Deterministic synthetic evidence exercise; no network or live tool calls."""

import argparse
import json
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path


RESULTS = {"UNKNOWN", "NO_RESULTS_RETURNED", "RESULTS_OBSERVED"}
STATUSES = {"success", "partial", "accessdenied", "unsupported", "timedout"}
CASE_FIELDS = {
    "scenario_id", "synthetic", "as_of_utc", "max_age_seconds",
    "future_tolerance_seconds", "required_sources", "observations",
    "expected_result",
}
ROW_FIELDS = {"source", "status", "observed_at_utc", "row_count"}
FIXTURES = Path(__file__).resolve().parents[1] / "examples" / "scenarios.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def utc_time(value: object) -> datetime:
    require(isinstance(value, str), "timestamp must be a UTC string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("invalid timestamp") from None
    require(parsed.utcoffset() == timedelta(0), "timestamp must include UTC offset")
    return parsed


def summarize(case: dict) -> dict:
    require(isinstance(case, dict) and set(case) == CASE_FIELDS, "invalid case fields")
    require(case["synthetic"] is True, "only explicitly synthetic data is accepted")
    require(
        isinstance(case["scenario_id"], str)
        and re.fullmatch(r"[a-z][a-z0-9-]*", case["scenario_id"]) is not None,
        "invalid scenario ID",
    )
    require(
        isinstance(case["expected_result"], str) and case["expected_result"] in RESULTS,
        "invalid expected result",
    )
    for field, minimum in (("max_age_seconds", 1), ("future_tolerance_seconds", 0)):
        require(type(case[field]) is int and case[field] >= minimum, "invalid time budget")
    reference = utc_time(case["as_of_utc"])
    required = case["required_sources"]
    require(isinstance(required, list) and len(required) > 0, "required scope is empty")
    require(
        all(isinstance(s, str) and re.fullmatch(r"SYNTHETIC_[A-Z0-9_]+", s) for s in required),
        "sources must use synthetic labels",
    )
    require(len(required) == len(set(required)), "duplicate required source")
    require(isinstance(case["observations"], list), "observations must be an array")
    observations = {}
    gaps = []
    rows = []
    for row in case["observations"]:
        require(isinstance(row, dict) and set(row) == ROW_FIELDS, "invalid observation fields")
        source = row["source"]
        require(isinstance(source, str) and source in required, "unexpected source")
        require(source not in observations, "duplicate observation source")
        status = row["status"]
        require(isinstance(status, str) and status in STATUSES, "invalid source status")
        count = row["row_count"]
        valid_count = type(count) is int and count >= 0
        if status == "success":
            require(valid_count, "successful source requires a nonnegative row count")
        elif status == "partial":
            require(count is None or valid_count, "invalid partial row count")
        else:
            require(count is None, "unavailable source must retain null row count")
        age = (reference - utc_time(row["observed_at_utc"])).total_seconds()
        if status != "success":
            gaps.append(f"{source}:{status}")
        if age > case["max_age_seconds"]:
            gaps.append(f"{source}:stale")
        if age < -case["future_tolerance_seconds"]:
            gaps.append(f"{source}:future-clock-skew")
        observations[source] = row
    for source in required:
        if source not in observations:
            gaps.append(f"{source}:missing")
            rows.append({
                "source": source, "status": "missing",
                "observed_at_utc": None, "row_count": None,
            })
        else:
            rows.append(dict(observations[source]))
    result = "UNKNOWN"
    if not gaps:
        result = (
            "RESULTS_OBSERVED" if any(row["row_count"] > 0 for row in rows)
            else "NO_RESULTS_RETURNED"
        )
    return {
        "evidence_class": "SYNTHETIC",
        "scenario_id": case["scenario_id"],
        "as_of_utc": case["as_of_utc"],
        "result": result,
        "coverage_gaps": gaps,
        "sources": rows,
        "limitation": "Teaching source/window only; no live or global health assertion.",
    }


def load_cases() -> list:
    cases = json.loads(FIXTURES.read_text(encoding="utf-8"))
    require(isinstance(cases, list) and len(cases) > 0, "fixtures must be a nonempty array")
    seen = set()
    for case in cases:
        summarize(case)
        require(case["scenario_id"] not in seen, "duplicate scenario ID")
        seen.add(case["scenario_id"])
    return cases


def main() -> int:
    try:
        cases = load_cases()
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument(
            "--scenario", choices=["all"] + [case["scenario_id"] for case in cases],
            default="all",
        )
        args = parser.parse_args()
        selected = [
            case for case in cases
            if args.scenario == "all" or case["scenario_id"] == args.scenario
        ]
        print(json.dumps([summarize(case) for case in selected], indent=2))
        return 0
    except (OSError, ValueError) as error:
        print(f"Offline replay failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
