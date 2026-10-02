import copy
import json
from pathlib import Path
import subprocess
import unittest

from validate_inputs import alert_name, validate


ROOT = Path(__file__).resolve().parent
SUB = "00000000-0000-0000-0000-000000000000"
MACHINE = f"/subscriptions/{SUB}/resourceGroups/example-arc/providers/Microsoft.HybridCompute/machines/example-server"
OWNER = "11111111-1111-4111-8111-111111111111"


def parameters():
    return {"parameters": {
        "ownershipId": {"value": OWNER},
        "machineResourceIds": {"value": [MACHINE]},
        "actionGroupResourceIds": {"value": []},
    }}


class Inputs(unittest.TestCase):
    def test_valid_no_actions(self):
        self.assertEqual(validate(parameters(), SUB), [alert_name(OWNER, MACHINE)])

    def test_names_are_bound_to_target_not_array_order_or_case(self):
        ids = [MACHINE, MACHINE + "2", MACHINE.replace("example-arc", "other-group")]
        names = [alert_name(OWNER, target) for target in ids]
        self.assertEqual(len(set(names)), 3)
        self.assertEqual(names[0], alert_name(OWNER.upper(), MACHINE.upper()))
        self.assertEqual(names[::-1], [alert_name(OWNER, target) for target in ids[::-1]])
        self.assertNotEqual(names[0], alert_name("22222222-2222-4222-8222-222222222222", MACHINE))

    def test_optional_actions(self):
        value = parameters()
        del value["parameters"]["actionGroupResourceIds"]
        validate(value, SUB)
        value["parameters"]["actionGroupResourceIds"] = {"value": [
            f"/subscriptions/{SUB}/resourceGroups/example-arc/providers/Microsoft.Insights/actionGroups/example"
        ]}
        validate(value, SUB)

    def test_invalid_scopes(self):
        for invalid in ("", " ", MACHINE + "/", MACHINE + "/extensions/agent",
                        MACHINE.rsplit("/", 1)[0] + "/", MACHINE + "*",
                        MACHINE.replace("example-server", "bad name"),
                        MACHINE.replace("Microsoft.HybridCompute", "Microsoft.Compute"),
                        f"/subscriptions/{SUB}", MACHINE.replace(SUB, OWNER)):
            with self.subTest(invalid=invalid):
                value = parameters()
                value["parameters"]["machineResourceIds"]["value"] = [invalid]
                with self.assertRaises(ValueError):
                    validate(value, SUB)

    def test_invalid_arrays(self):
        for invalid in ([], None, MACHINE, [None], [MACHINE, MACHINE.upper()]):
            with self.subTest(invalid=invalid):
                value = parameters()
                value["parameters"]["machineResourceIds"]["value"] = invalid
                with self.assertRaises(ValueError):
                    validate(value, SUB)

    def test_invalid_owner(self):
        for invalid in ("", " " * 36, SUB, "[newGuid()]", "z" * 36):
            value = parameters()
            value["parameters"]["ownershipId"]["value"] = invalid
            with self.assertRaises(ValueError):
                validate(value, SUB)

    def test_invalid_action_group(self):
        value = parameters()
        value["parameters"]["actionGroupResourceIds"]["value"] = [MACHINE]
        with self.assertRaises(ValueError):
            validate(value, SUB)

    def test_unexpected_or_nonliteral_parameters(self):
        for entry in ({"value": OWNER, "reference": {}}, {"reference": {}}):
            value = parameters()
            value["parameters"]["ownershipId"] = entry
            with self.assertRaises(ValueError):
                validate(value, SUB)
        value = parameters()
        value["parameters"]["location"] = {"value": "other"}
        with self.assertRaises(ValueError):
            validate(value, SUB)


class CompiledTemplate(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["bicep", "build", str(ROOT / "main.bicep"), "--stdout"],
            check=True, capture_output=True, text=True,
        )
        cls.template = json.loads(result.stdout)
        resources = cls.template["resources"]
        cls.resources = list(resources.values()) if isinstance(resources, dict) else resources
        cls.rule = cls.resources[0]

    def test_only_global_enabled_alerts_one_per_machine(self):
        self.assertEqual(len(self.resources), 1)
        self.assertEqual(self.rule["type"], "Microsoft.Insights/activityLogAlerts")
        self.assertEqual(self.rule["apiVersion"], "2020-10-01")
        self.assertEqual(self.rule["location"], "global")
        self.assertIs(self.rule["properties"]["enabled"], True)
        self.assertNotIn("identity", self.rule)
        self.assertEqual(self.rule["copy"], {
            "name": "connectivityAlerts",
            "count": "[length(parameters('machineResourceIds'))]",
        })

    def test_owned_name_and_tag(self):
        self.assertIn("parameters('ownershipId')", self.rule["name"])
        self.assertEqual(self.rule["name"],
                         "[format('arc-connectivity-single-{0}', guid(toLower(parameters('ownershipId')), toLower(parameters('machineResourceIds')[copyIndex()])))]")
        self.assertEqual(self.rule["tags"]["arc-connectivity-owner"], "[parameters('ownershipId')]")

    def test_exact_scopes_and_equality(self):
        self.assertEqual(self.rule["properties"]["scopes"], ["[parameters('machineResourceIds')[copyIndex()]]"])
        conditions = self.rule["properties"]["condition"]["allOf"]
        self.assertEqual(len(conditions), 5)
        self.assertEqual(conditions[4], {
            "field": "resourceId",
            "equals": "[parameters('machineResourceIds')[copyIndex()]]",
        })
        for condition in conditions:
            self.assertEqual(set(condition), {"field", "equals"})
            self.assertNotIn("*", condition["equals"])

    def test_four_machine_exact_set_and_prefix_counterexamples(self):
        ids = [MACHINE.rsplit("/", 1)[0] + "/" + name
               for name in ("AzLHOST1", "AzLHOST2", "app01", "db01")]
        expression = "[parameters('machineResourceIds')[copyIndex()]]"
        self.assertEqual(self.rule["properties"]["scopes"], [expression])
        conditions = self.rule["properties"]["condition"]["allOf"]
        expanded = [
            [{**c, "equals": target if c["equals"] == expression else c["equals"]}
             for c in conditions]
            for target in ids
        ]
        self.assertEqual({c[-1]["equals"] for c in expanded}, set(ids))
        for target, rule in zip(ids, expanded):
            event = {c["field"]: c["equals"] for c in rule}
            def matches(resource_id):
                candidate = {**event, "resourceId": resource_id}
                return all(candidate[c["field"]].lower() == c["equals"].lower() for c in rule)
            self.assertTrue(matches(target.upper()))
            for other in [i for i in ids if i != target] + [
                target + "2", target + "-same-prefix", target + "/extensions/agent",
                target.replace("example-arc", "other-group"), target.replace(SUB, OWNER),
            ]:
                self.assertFalse(matches(other), other)
        foo = MACHINE.rsplit("/", 1)[0] + "/foo"
        self.assertNotEqual(foo.lower(), (foo + "2").lower())
        # Exercise the compiled equality expression with foo as the scope target.
        foo_rule = [{**c, "equals": foo if c["equals"] == expression else c["equals"]} for c in conditions]
        self.assertFalse(all(
            ({c["field"]: c["equals"] for c in foo_rule} | {"resourceId": foo + "2"})[c["field"]].lower()
            == c["equals"].lower() for c in foo_rule
        ))

    def test_transition_fields_without_cause_or_event_status_filter(self):
        conditions = self.rule["properties"]["condition"]["allOf"]
        self.assertEqual({c["field"]: c["equals"] for c in conditions[:4]}, {
            "category": "ResourceHealth",
            "resourceType": "Microsoft.HybridCompute/machines",
            "properties.previousHealthStatus": "Available",
            "properties.currentHealthStatus": "Unavailable",
        })

    def test_no_default_actions_or_query(self):
        self.assertEqual(self.template["parameters"]["actionGroupResourceIds"]["defaultValue"], [])
        actions = self.rule["properties"]["actions"]["copy"][0]
        self.assertEqual(actions["name"], "actionGroups")
        self.assertEqual(actions["count"], "[length(parameters('actionGroupResourceIds'))]")
        self.assertNotIn("query", json.dumps(self.rule["properties"]).lower())

    def test_transition_semantics_not_inventory_or_recovery(self):
        conditions = self.rule["properties"]["condition"]["allOf"][:4]
        event = {c["field"]: c["equals"] for c in conditions}

        def matches(candidate):
            return all(str(candidate.get(c["field"], "")).lower() == c["equals"].lower() for c in conditions)

        self.assertTrue(matches(event))
        for previous, current in (("Unavailable", "Unavailable"), ("Unknown", "Unavailable"),
                                  ("Unavailable", "Available"), ("", "")):
            candidate = copy.deepcopy(event)
            candidate.update({"properties.previousHealthStatus": previous, "properties.currentHealthStatus": current})
            self.assertFalse(matches(candidate))
        for reason in ("UserInitiated", "PlatformInitiated", "Unknown"):
            self.assertTrue(matches({**event, "properties.cause": reason}))


if __name__ == "__main__":
    unittest.main()
