"""Offline contract model, not an Azure KQL interpreter or live event capture."""
import json
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
QUERY = (ROOT / "stopped-transition.kql").read_text()
TEMPLATE = (ROOT / "main.bicep").read_text()
TARGET = "/subscriptions/00000000-0000-4000-8000-000000000000/resourceGroups/rg-demo/providers/Microsoft.HybridCompute/machines/demo-windows-01"
STOP = "The Print Spooler service entered the stopped state."
RUN = "The Print Spooler service entered the running state."


def event(**changes):
    row = dict(_ResourceId=TARGET, EventLog="System", Source="Service Control Manager",
               EventID=7036, RenderedDescription=STOP,
               EventData='<DataItem><EventData><Data Name="param1">Print Spooler</Data>'
                         '<Data Name="param2">stopped</Data></EventData></DataItem>',
               source_age_seconds=60, ingestion_age_seconds=30)
    row.update(changes)
    return row


def observed(rows):
    return [r for r in rows if (r["_ResourceId"] or "").lower() == TARGET.lower()
            and r["EventLog"] == "System" and r["Source"] == "Service Control Manager"
            and r["EventID"] == 7036 and (r["RenderedDescription"] or "").strip() == STOP
            and r["source_age_seconds"] is not None
            and 0 <= r["source_age_seconds"] <= 600
            and r["ingestion_age_seconds"] is not None
            and 0 <= r["ingestion_age_seconds"] <= 300]


class Contract(unittest.TestCase):
    def test_canonical_query_shape(self):
        for fragment in (
            'dynamic(__TARGET_RESOURCE_IDS__)', '_ResourceId in~ (TargetIds)',
            'TimeGenerated >= ago(10m) and TimeGenerated <= now()',
            'EventLog == "System" and Source == "Service Control Manager" and EventID == 7036',
            'EventIngestedUtc = ingestion_time()', 'isnotnull(EventIngestedUtc)',
            'EventIngestedUtc >= ago(5m) and EventIngestedUtc <= now()',
            'trim(@"\\s+", RenderedDescription) == "' + STOP + '"',
            'CurrentState = "Unknown"', 'Evidence = "StoppedTransitionObserved"',
        ):
            self.assertIn(fragment, QUERY)
        self.assertNotIn("summarize", QUERY)  # No empty-input aggregate implies healthy.
        self.assertNotIn("arg_max", QUERY)  # No inferred current-state/latest-event oracle.

    def test_template_contract(self):
        for fragment in ("'Microsoft-Event'", "EventID=7036", "param1",
                         "Print Spooler", "scope: machine", "autoMitigate: false",
                         "skipQueryValidation: false", "threshold: 0",
                         "timeAggregation: 'Count'", "param deployAlert bool = false",
                         "if (deployAlert)", "enabled: true",
                         "loadTextContent('stopped-transition.kql')", "string([machine.id])"):
            self.assertIn(fragment, TEMPLATE)
        for forbidden in ("roleAssignments", "virtualMachines/extensions", "7031", "7034"):
            self.assertNotIn(forbidden, TEMPLATE)

    def test_compiled_template(self):
        compiled = json.loads(subprocess.check_output(
            ["bicep", "build", str(ROOT / "main.bicep"), "--stdout"], text=True))
        resources = compiled["resources"]
        if isinstance(resources, dict):
            resources = list(resources.values())
        existing = [r for r in resources if r.get("existing")]
        self.assertEqual(["Microsoft.HybridCompute/machines"], [r["type"] for r in existing])
        resources = [r for r in resources if not r.get("existing")]
        self.assertEqual(3, len(resources))
        dcr = next(r for r in resources if r["type"].endswith("/dataCollectionRules"))
        assoc = next(r for r in resources if r["type"].endswith("/dataCollectionRuleAssociations"))
        alert = next(r for r in resources if r["type"].endswith("/scheduledQueryRules"))
        self.assertEqual(["Microsoft-Event"], dcr["properties"]["dataFlows"][0]["streams"])
        self.assertIn("machine", assoc["scope"].lower())
        self.assertEqual("[parameters('deployAlert')]", alert["condition"])
        self.assertFalse(alert["properties"]["autoMitigate"])
        self.assertEqual("Count", alert["properties"]["criteria"]["allOf"][0]["timeAggregation"])
        self.assertFalse(compiled["parameters"]["deployAlert"]["defaultValue"])

    def test_stop_and_outer_whitespace(self):
        self.assertEqual(1, len(observed([event(RenderedDescription=STOP + "\r\n")])))

    def test_running_is_not_a_stop(self):
        self.assertEqual([], observed([event(RenderedDescription=RUN)]))

    def test_stop_then_start_is_historical_evidence_not_current_state(self):
        stop = event(source_age_seconds=120)
        self.assertEqual([stop], observed([stop, event(RenderedDescription=RUN)]))

    def test_localized_renamed_partial_and_ambiguous_descriptions(self):
        for text in ("Der Dienst Druckwarteschlange wurde beendet.", "Spooler stopped",
                     STOP.replace("Print Spooler", "Other Print Spooler"), STOP + RUN, ""):
            with self.subTest(text=text):
                self.assertEqual([], observed([event(RenderedDescription=text)]))

    def test_cross_target_log_provider_and_id(self):
        for change in (dict(_ResourceId=TARGET + "-other"), dict(EventLog="Application"),
                       dict(Source="Other"), dict(EventID=7031)):
            self.assertEqual([], observed([event(**change)]))
        self.assertEqual(1, len(observed([event(_ResourceId=TARGET.upper())])))

    def test_source_and_ingestion_age_independent(self):
        for change in (dict(source_age_seconds=601, ingestion_age_seconds=0),
                       dict(source_age_seconds=-1), dict(ingestion_age_seconds=301),
                       dict(ingestion_age_seconds=-1), dict(ingestion_age_seconds=None)):
            self.assertEqual([], observed([event(**change)]))
        self.assertEqual(1, len(observed([event(source_age_seconds=600, ingestion_age_seconds=300)])))

    def test_no_data_and_stop_before_collection_are_not_healthy(self):
        self.assertEqual([], observed([]))
        self.assertEqual([], observed([event(source_age_seconds=3600)]))
        self.assertIn('CurrentState = "Unknown"', QUERY)

    def test_missing_identity_description_or_time_is_not_evidence(self):
        for change in (dict(_ResourceId=None), dict(RenderedDescription=None),
                       dict(source_age_seconds=None)):
            self.assertEqual([], observed([event(**change)]))


if __name__ == "__main__":
    unittest.main()
