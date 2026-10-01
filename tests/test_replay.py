import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

from scripts.replay import load_cases, summarize


ROOT = Path(__file__).resolve().parents[1]


class ReplayTests(unittest.TestCase):
    def setUp(self):
        self.cases = load_cases()
        self.empty = copy.deepcopy(next(
            case for case in self.cases if case["scenario_id"] == "complete-empty"
        ))

    def test_all_fixture_answers_and_output_shape(self):
        for case in self.cases:
            with self.subTest(case=case["scenario_id"]):
                result = summarize(case)
                self.assertEqual(result["result"], case["expected_result"])
                self.assertEqual(result["evidence_class"], "SYNTHETIC")
                self.assertEqual(len(result["sources"]), len(case["required_sources"]))
                self.assertEqual(set(result), {
                    "evidence_class", "scenario_id", "as_of_utc", "result",
                    "coverage_gaps", "sources", "limitation",
                })

    def test_answer_key_does_not_drive_computation(self):
        self.empty["expected_result"] = "UNKNOWN"
        self.assertEqual(summarize(self.empty)["result"], "NO_RESULTS_RETURNED")

    def test_denied_and_missing_counts_stay_unknown(self):
        for case in self.cases:
            if case["scenario_id"] in {"provider-denied", "missing-source"}:
                result = summarize(case)
                self.assertEqual(result["result"], "UNKNOWN")
                self.assertIsNone(result["sources"][1]["row_count"])
                self.assertTrue(result["coverage_gaps"])

    def test_partial_count_is_retained_but_not_complete(self):
        case = next(c for c in self.cases if c["scenario_id"] == "partial-source")
        result = summarize(case)
        self.assertEqual(result["result"], "UNKNOWN")
        self.assertEqual(result["sources"][0]["row_count"], 1)

    def test_freshness_boundaries(self):
        for timestamp, expected in (
            ("2000-01-01T00:00:00Z", "NO_RESULTS_RETURNED"),
            ("1999-12-31T23:59:59Z", "UNKNOWN"),
            ("2000-01-01T00:02:05Z", "NO_RESULTS_RETURNED"),
            ("2000-01-01T00:02:06Z", "UNKNOWN"),
        ):
            with self.subTest(timestamp=timestamp):
                self.empty["observations"][0]["observed_at_utc"] = timestamp
                self.assertEqual(summarize(self.empty)["result"], expected)

    def test_invalid_timestamps_are_not_empty_success(self):
        for timestamp in ("", "invalid", "2000-01-01T00:01:00", "2000-01-01T01:01:00+01:00", None):
            with self.subTest(timestamp=timestamp):
                self.empty["observations"][0]["observed_at_utc"] = timestamp
                with self.assertRaises(ValueError):
                    summarize(self.empty)

    def test_unavailable_statuses_stay_unknown(self):
        for status in ("accessdenied", "unsupported", "timedout"):
            with self.subTest(status=status):
                self.empty["observations"][0].update(status=status, row_count=None)
                self.assertEqual(summarize(self.empty)["result"], "UNKNOWN")

    def test_reject_invalid_counts(self):
        for count in (-1, True, "0", 0.5, None):
            with self.subTest(count=count):
                self.empty["observations"][0]["row_count"] = count
                with self.assertRaises(ValueError):
                    summarize(self.empty)

    def test_reject_non_synthetic_or_malformed_scope(self):
        mutations = (
            lambda c: c.update(synthetic=False),
            lambda c: c.update(required_sources=[]),
            lambda c: c["required_sources"].append(c["required_sources"][0]),
            lambda c: c["observations"].append(copy.deepcopy(c["observations"][0])),
            lambda c: c["observations"][0].update(source="NOT_SYNTHETIC"),
            lambda c: c["observations"][0].update(status="accessdenied", row_count=0),
            lambda c: c.update(max_age_seconds=True),
            lambda c: c.update(future_tolerance_seconds=-1),
            lambda c: c.update(unrecognized="field"),
        )
        for mutate in mutations:
            case = copy.deepcopy(self.empty)
            mutate(case)
            with self.subTest(case=case), self.assertRaises(ValueError):
                summarize(case)

    def test_cli_all_is_json_and_unknown_scenario_fails(self):
        command = [sys.executable, "-B", str(ROOT / "scripts" / "replay.py")]
        valid = subprocess.run(command + ["--scenario", "all"], capture_output=True, text=True)
        self.assertEqual(valid.returncode, 0, valid.stderr)
        self.assertEqual(len(json.loads(valid.stdout)), len(self.cases))
        invalid = subprocess.run(command + ["--scenario", "not-a-case"], capture_output=True, text=True)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertEqual(invalid.stdout, "")
        self.assertIn("invalid choice", invalid.stderr)


if __name__ == "__main__":
    unittest.main()
