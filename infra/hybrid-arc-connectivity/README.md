# Arc connection-state transition alert

One additive, enabled `Microsoft.Insights/activityLogAlerts@2020-10-01`
resource **per explicitly selected existing Arc-enabled server**, in `global`.
No query, Log Analytics dependency, managed identity, Reader grant, polling
service, guest change or new notification destination. Existing AMA heartbeat,
CPU, memory, disk and coverage rules and DCRs remain separate and untouched.

## Signal and limits

The Connected Machine agent sends a heartbeat every five minutes. Azure
considers a machine disconnected after more than 15 minutes without it.
Microsoft recommends a **Resource Health Available → Unavailable** alert for
this scenario. This is not the AMA `Heartbeat` table.

The rule matches `category=ResourceHealth`,
`resourceType=Microsoft.HybridCompute/machines`,
`properties.previousHealthStatus=Available` and
`properties.currentHealthStatus=Unavailable`. Each scope is a complete machine
ID; each rule has exactly one scope and a flat `allOf` containing exactly one
`resourceId` equality for that same ID. Because this API treats scopes as
prefixes, equality excludes similarly named machines and descendants, including
`foo2` when the target is `foo`, and `foo/extensions/agent`.
There is deliberately no cause/reason or event-status filter: user-initiated
network loss must not be excluded, and actual status representations may vary.

This is **an event detector, not current inventory**. A server already
disconnected before the rule was enabled, never connected, or transitioning
from Unknown does not satisfy this transition. Ingestion and evaluation delay
add to detection time; 15 minutes is not an end-to-end notification SLA.
No events/zero alerts is **UNKNOWN**, not healthy. Use fresh Connected Machine
status and Resource Health GETs for current observations. Neither event nor
missing telemetry diagnoses power loss, network failure, agent failure or
application health. Recovery and automatic incident resolution are not implicit:
this rule does not match Unavailable → Available.

Action groups default to empty: no action-group notification is configured.
Optionally supply existing, approved action group IDs; this creates none.
Native SRE routing, fired-alert ingestion and initial/final Teams messages require
separate acceptance evidence. Compilation, preflight and what-if prove none of
those outcomes.

## Provider-rejection revision and footprint

An earlier single-rule candidate combined multiple exact machine scopes with a
nested `resourceId` `anyOf`. ARM validation and what-if passed, but the actual
Monitor resource provider rejected creation with `ScopeMismatch` ("The resourceId
specified in the condition is not in the right scope."). This does **not**
establish that `anyOf` is generally unsupported, nor explain the provider's
internal validation algorithm.

This revision removes both multi-scope and multi-resource-condition interaction:
one machine scope, one matching flat resource-ID equality, unchanged category,
resource type and transition. The official creation guide supports individual
resource scopes; the REST schema documents prefix scopes, flat `allOf` leaves,
`resourceId`, and case-insensitive equality. These establish the intended
semantics, **not actual provider acceptance of this revised combination**.
No documented requirement to broaden to resource-group scope was found in those
references; no resource-group/subscription scope fallback is included. If the
provider rejects this candidate, stop for coordinator review, not scope widening.

For four selected machines the footprint is **four new rules, not one** (+3
versus the failed design, +4 versus its absent live resource). They have four
independent ownership/GET/routing verification obligations and consume four
activity-log rule slots. There is no additional query, workspace or ingestion
component. Review current Azure Monitor pricing and notification charges before
approval; the changed count must not be presented as an approved cost-neutral
change. Action groups remain empty by default.

## Prepare and test (no deployment)

Use Bicep CLI and Python 3 (standard library only), from the repository root:

```powershell
bicep build .\infra\hybrid-arc-connectivity\main.bicep --stdout
bicep build-params .\infra\hybrid-arc-connectivity\main.example.bicepparam --stdout
python -B -m unittest discover -s .\infra\hybrid-arc-connectivity -p 'test_*.py' -v
```

Copy the example privately; replace the illustrative IDs with exact IDs returned
by current GETs and generate a fresh ownership UUID. Keep real bindings and
receipts out of portable source. Each name is
`arc-connectivity-single-<guid(lowercase ownership UUID, lowercase full machine ID)>`.
ARM's deterministic UUID is bound to the complete target, independent of array
order and ID case; the new prefix cannot collide with the failed design's name.
The `arc-connectivity-owner` tag retains the ownership UUID. A fresh UUID and
exact absence checks are still mandatory; a deterministic name is not ownership
or overwrite permission. The output is now `alertResourceIds` (array).
Compile the private `.bicepparam` to an ARM parameters JSON file, then run:

```powershell
python -B .\infra\hybrid-arc-connectivity\validate_inputs.py `
  .\private.parameters.json --subscription '<explicit-subscription-uuid>'
```

This mandatory offline gate rejects empty names, nonliteral/wrong-type IDs,
broad scopes, descendants, duplicate IDs, invalid ownership UUIDs and
cross-subscription references. It is intentionally conservative about names.
Bicep supplies array/string bounds; portable deployment assertions are not
enabled through experimental features. Do not bypass the input gate when
invoking ARM directly.

## Manual preflight and application gate

1. Select the approved subscription explicitly on every Azure call; never change
   global account context. Validate the compiled parameters above.
2. GET each exact machine and optional action group; verify returned ID/type,
   nonempty name and intended subscription. Record full responses, UTC times,
   current Arc status and the machine's
   `Microsoft.ResourceHealth/availabilityStatuses/current` response. If support
   is absent or ambiguous, stop for review; do not add a substitute polling system.
3. GET every exact proposed alert ID. Require **ResourceNotFound/404**; a permission
   failure or other error is not absence. A same-name resource, even with matching
   tags, is not permission to adopt or overwrite it.
4. Preserve existing monitoring full GETs/hashes. Compile and retain exact
   template/parameter hashes and ownership UUID in a private candidate plan.
5. Use ARM deployment **validate** and **whatIf** analysis endpoints with
   `mode=Incremental`; neither is an apply. Inspect the complete, successful
   what-if result: exactly one **Create per machine** for the complete proposed
   alert-ID set (four machines require four Creates), no
   Modify/Delete/Deploy/unsupported changes. Unrelated Ignore/NoChange entries
   are not modifications; retain them in the receipt. Never use Complete mode.
6. **Stop for separate live approval and source review.** Recheck absence,
   freshness, hashes and the exact Create set immediately before a separately
   authorized deployment. This starter includes no automatic apply/cleanup.
7. After any separately approved application, retain a full GET of every exact
   alert, timestamp, returned ID, name, type, enabled flag, ownership tags,
   scopes, all conditions, action groups and deployment result. Compare every
   value to the approved candidate and verify previous monitoring unchanged.
   Retain the successful alert. Any rollback is separately approved and
   requires original full GET ownership/drift evidence; tags alone are not enough.

## Official references

- [Disconnected scenarios and recommended Arc Resource Health transition](https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-connectivity)
- [Connected Machine agent: heartbeat cadence](https://learn.microsoft.com/azure/azure-arc/servers/agent-overview)
- [Create Resource Health alerts](https://learn.microsoft.com/azure/service-health/resource-health-alert-arm-template-guide)
  (despite its URL, the current page is a portal guide).
- [Activity Log Resource Health schema and exact property names](https://learn.microsoft.com/azure/azure-monitor/fundamentals/activity-log-schema#resource-health-category)
- [Activity-log alert resource schema, supported locations and prefix scopes](https://learn.microsoft.com/azure/templates/microsoft.insights/2020-10-01/activitylogalerts)
- [Individual-resource scope and optional actions](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-activity-log-alert-rule)
- [REST schema and flat allOf sample](https://learn.microsoft.com/rest/api/monitor/activity-log-alerts/create-or-update?view=rest-monitor-2020-10-01)
- [ARM deterministic guid algorithm](https://learn.microsoft.com/azure/azure-resource-manager/templates/template-functions-string#guid)
- [Azure Monitor pricing](https://azure.microsoft.com/pricing/details/monitor/)
