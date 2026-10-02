"""Offline gate for compiled ARM parameters; makes no Azure calls."""

import argparse
import json
import re
from pathlib import Path
from uuid import UUID, uuid5


GUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
RESOURCE_ID = re.compile(
    rf"/subscriptions/(?P<subscription>{GUID})/resourceGroups/"
    r"(?P<group>[A-Za-z0-9_.()-]+)/providers/(?P<type>[^/]+/[^/]+)/"
    r"(?P<name>[A-Za-z0-9_.()-]+)",
    re.IGNORECASE,
)

def alert_name(owner, machine_id):
    """Mirror ARM guid(): documented namespace and hyphen-joined arguments."""
    namespace = UUID("11fb06fb-712d-4ddd-98c7-e71bbd588830")
    return f"arc-connectivity-single-{uuid5(namespace, owner.lower() + '-' + machine_id.lower())}"


def validate(parameters, subscription_id):
    """Require literal full IDs, nonempty names, exact types and one subscription."""
    try:
        subscription = str(UUID(subscription_id))
    except (ValueError, TypeError, AttributeError) as error:
        raise ValueError("Expected an explicit subscription UUID") from error
    if not isinstance(parameters, dict) or "parameters" not in parameters:
        raise ValueError("Expected an ARM parameters document")
    entries = parameters["parameters"]
    allowed = {"ownershipId", "machineResourceIds", "actionGroupResourceIds"}
    if not isinstance(entries, dict) or set(entries) - allowed:
        raise ValueError("Unexpected parameters")
    values = {}
    for key, entry in entries.items():
        if not isinstance(entry, dict) or set(entry) != {"value"}:
            raise ValueError(f"{key} must contain one literal value")
        values[key] = entry["value"]
    owner = values.get("ownershipId")
    if not isinstance(owner, str) or not re.fullmatch(GUID, owner, re.IGNORECASE):
        raise ValueError("ownershipId must be a canonical UUID")
    if UUID(owner).int == 0:
        raise ValueError("ownershipId must not be the nil UUID")
    for key, resource_type, required in (
        ("machineResourceIds", "Microsoft.HybridCompute/machines", True),
        ("actionGroupResourceIds", "Microsoft.Insights/actionGroups", False),
    ):
        ids = values.get(key, [] if not required else None)
        if not isinstance(ids, list) or (required and not ids):
            raise ValueError(f"{key} must be an array with {'at least one ID' if required else 'zero or more IDs'}")
        seen = set()
        for resource_id in ids:
            match = RESOURCE_ID.fullmatch(resource_id) if isinstance(resource_id, str) else None
            if not match or match["type"].lower() != resource_type.lower():
                raise ValueError(f"{key} requires exact {resource_type} IDs with nonempty names")
            if match["subscription"].lower() != subscription:
                raise ValueError(f"{key} must be in the explicitly selected subscription")
            if resource_id.lower() in seen:
                raise ValueError(f"{key} contains duplicate IDs")
            seen.add(resource_id.lower())
    return [alert_name(owner, machine_id) for machine_id in values["machineResourceIds"]]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parameters", type=Path)
    parser.add_argument("--subscription", required=True)
    args = parser.parse_args()
    try:
        names = validate(json.loads(args.parameters.read_text(encoding="utf-8-sig")), args.subscription)
    except (ValueError, OSError) as error:
        parser.exit(1, f"FAIL: {error}\n")
    print(f"PASS: input shape only; {len(names)} proposed alerts: {', '.join(names)}")
    print("Existence, Resource Health support, ownership absence, permissions and exactly one Create per machine still require fresh read-only preflight.")
