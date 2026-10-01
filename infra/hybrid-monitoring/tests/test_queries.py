"""Contract and reference-model tests; live KQL execution is a separate preflight gate."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def missing(expected, rows, now=100, freshness=10):
    recent = {rid.lower() for rid, time in rows if now - freshness < time <= now}
    return {rid.lower() for rid in expected} - recent


def sustained(rows, threshold, high=True, required=3, minimum_samples=3):
    """Rows are (resource, disk/instance, closed-five-minute-bin, percent)."""
    series = {}
    for resource, instance, bucket, value in rows:
        if 0 <= value <= 100:
            series.setdefault((resource.lower(), instance.lower()), {}).setdefault(bucket, []).append(value)
    result = set()
    for key, buckets in series.items():
        if len(buckets) != required or min(map(len, buckets.values())) < minimum_samples:
            continue
        means = [sum(v) / len(v) for v in buckets.values()]
        if (min(means) > threshold if high else max(means) < threshold):
            result.add(key)
    return result


class QueryTests(unittest.TestCase):
    def test_whole_set_absent_and_never_seen(self):
        self.assertEqual(missing(["/A", "/B"], []), {"/a", "/b"})
        self.assertEqual(missing(["/A", "/B"], [("/a", 99)]), {"/b"})

    def test_stale_boundary_future_and_case(self):
        self.assertEqual(missing(["/A", "/B", "/C"], [("/a", 90), ("/B", 101), ("/c", 99)]), {"/a", "/b"})

    def test_cpu_percent_not_fraction_and_sustained(self):
        rows = [("/A", "_Total", b, 95) for b in range(3) for _ in range(3)]
        self.assertEqual(sustained(rows, 90), {("/a", "_total")})
        self.assertEqual(sustained(rows[:-1], 90), set())
        self.assertEqual(sustained(rows + [("/a", "_Total", 1, 0)] * 4, 90), set())
        self.assertEqual(sustained([(r, i, b, .95) for r, i, b, _ in rows], 90), set())

    def test_disk_instances_not_host_average(self):
        rows = [("/A", disk, b, value) for disk, value in [("C:", 5), ("D:", 80)] for b in range(3) for _ in range(3)]
        self.assertEqual(sustained(rows, 10, high=False), {("/a", "c:")})

    def test_memory_physical_available_bytes(self):
        available_bytes = 1024 * 1024 * 1024
        self.assertEqual(100 * (available_bytes / 1048576) / 16384, 6.25)

    def test_canonical_bicep_ingestion(self):
        bicep = (ROOT / "main.bicep").read_text()
        for name in ["inventory", "heartbeat", "cpu", "memory", "disk", "coverage"]:
            self.assertIn(f"loadTextContent('queries/{name}.kql')", bicep)
        self.assertIn("param enabled bool = true", bicep)
        self.assertIn("autoMitigate: true", bicep)
        self.assertIn("resourceIdColumn: '_ResourceId'", bicep)
        self.assertNotIn("Spooler", bicep)

    def test_missing_data_inventory_drives_join(self):
        text = (ROOT / "queries/heartbeat.kql").read_text()
        self.assertIn("Inventory\n| join kind=leftouter Recent", text)
        self.assertIn("TimeGenerated > ago(Freshness)", text)
        self.assertIn("TimeGenerated = now()", text)
        self.assertIn("tolower(_ResourceId)", text)
        self.assertIn("isnull(LastSeen)", text)
        coverage = (ROOT / "queries/coverage.kql").read_text()
        self.assertIn("Expected\n| join kind=leftouter Observed", coverage)
        self.assertIn("CoveredBins", coverage)

    def test_perf_contracts(self):
        for name in ["cpu", "memory", "disk"]:
            text = (ROOT / f"queries/{name}.kql").read_text()
            self.assertIn("TimeGenerated >= WindowStart and TimeGenerated < WindowEnd", text)
            self.assertIn("Bins == RequiredBins and LeastSamples >= MinSamples", text)
        self.assertIn("min(Average)", (ROOT / "queries/cpu.kql").read_text())
        self.assertIn("max(Average)", (ROOT / "queries/disk.kql").read_text())
        self.assertIn("1048576.0", (ROOT / "queries/memory.kql").read_text())

    def test_sample_is_not_private_inventory(self):
        targets = json.loads((ROOT / "targets.example.json").read_text())
        self.assertIn("00000000-0000-0000-0000-000000000000", targets[0]["resourceId"])


if __name__ == "__main__":
    unittest.main()
