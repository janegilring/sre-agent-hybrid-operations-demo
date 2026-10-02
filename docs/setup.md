# Setup, prerequisites, costs and permissions

Reviewed 2026-10-01. Product sources: [source register](sources.md).

## Reproducible offline scope

For buildable components, start with the [component table](../README.md):
the [SRE starter](../infra/sre-agent-starter/README.md),
[monitoring baseline](../infra/hybrid-monitoring/README.md), and
[Windows JEA capability](../tools/hybrid-server/README.md) include their own
prerequisites, validation, deployment and ownership-checked cleanup commands.
The [portable MCP implementation](../tools/private-mcp/README.md) now includes
locked .NET 10 build/test projects and explicit operator-owned network settings.
Optional [disk collection](../infra/hybrid-monitoring-collection/README.md) and
[Spooler recovery](../tools/hybrid-service-recovery/README.md) have separate
collection-ownership and human-approval requirements; neither is a whole-stack
installer or proof of live guest access.
The [service-event monitoring starter](../infra/hybrid-service-monitoring/README.md)
adds scoped DCR/association source and an optional English 7036 transition
rule. AMA installation is a prerequisite, zero events is UNKNOWN, and neither
current-state monitoring nor native approval is delivered.
The [Arc-connectivity component](../infra/hybrid-arc-connectivity/README.md)
adds one exact-scope transition rule per machine, without requiring Log Analytics.
Four targets require four activity-log rule slots; no broad scope is substituted.
For a complete lab foundation use the [pinned LocalBox route](localbox.md).

The remainder of this section describes only the optional synthetic replay.
Use Python 3.11+ and the two replay commands in the [README](../README.md).
No package installation, Azure subscription, GitHub write token, SRE service,
model deployment or cloud login is required once the files are available.
The exercise does not load environment variables, credentials or a binding file.
It creates no infrastructure and incurs no Azure or model charge.

`examples/scenarios.json` is a teaching format, not a native MCP, Azure Monitor
or Health Service response schema. `expected_result` is the presenter's answer
key. The replay computes outcomes independently and tests compare them.
Its 120-second age and five-second future-skew values are teaching fixture
policy, not a universal product guarantee.

## Additional whole-lab readiness

The component scripts do not automate this whole sequence. A live environment
still needs owner approval and independent reproduction evidence before use:

1. Establish supported Azure Local deployment type/release, registered system,
   exact read targets and verified infrastructure/workload classification.
   A nested-virtualization lab is a lab, not physical on-premises production.
2. Select an existing Azure SRE Agent with approved managed resource scope.
   Capture current connector, tool and response-plan configuration. Preserve
   unrelated existing demonstrations and monitoring.
3. Inspect existing native Health alerts/`AzureEdgeAlerts` first. Built-in health
   alerts do not require a new Log Analytics workspace or custom alert rule.
   For Insights/performance, separately prove actual collection, ingestion,
   namespace/table/dimensions, retention and access.
4. If using private MCP, supply a separately reviewed deployment: private route,
   supported authentication, TLS certificate lifecycle, restricted caller,
   nonadmin service, explicit node transport, fixed tools, JEA/provider rights,
   bounded outputs and independent audits. This repository supplies the ordinary
   Windows JEA guest component and portable MCP source, not a deployed host, and does
   not authorize granting missing rights.
5. If considering Arc guest execution, verify its separate preview/support,
   agent/network/local-policy prerequisites and action-specific permissions.
   Arc Connected is not execution proof. No Arc Run Command payload is included.
6. Before SRE knowledge ingestion, audit all Code Access, Knowledge base and
   GitHub tools. Restrict new retrieval to neutral runbooks, never this answer
   repository or private planning. Verify source citations in a fresh thread.
7. Before incident rehearsal, verify approved targets, matching alert payloads,
   Review mode, overlap with default plans and separately approved notification
   effects. Do not silently remove existing plans or change monitoring.

## Permission boundaries

| Need | Review requirement |
| --- | --- |
| Azure metadata reads | Least necessary actual resource scope; inspect inherited as well as direct permissions |
| Log/metric reads | Appropriate source-specific access and collection coverage; resource Reader alone is not proof |
| SRE Azure Monitor incident integration | Current Microsoft guidance documents Monitoring Contributor on the subscription; review breadth and existing assignments, not an automatic grant |
| Private node diagnostics | Separate Windows/JEA/provider authorization and independent nonadmin proof |
| Arc Run Command | Privileged guest script capability; not a read-only role or an RBAC script-content allowlist |
| GitHub runbook retrieval | Repository-restricted read-only authorization where supported; selection in a UI is not isolation |
| Teams/status updates | Explicit approved audience and message/status side effects; diagnostic read approval alone is insufficient |

Do not request credentials in prompts, grant broad runtime administrator roles or
add an alternate privileged transport when a provider denies a read.

## Cost review before any live provisioning

| Component | Cost boundary |
| --- | --- |
| Offline fixture replay | Local execution only; no Azure/model charge |
| Native Azure Local health alerts | Documented no additional charge for the built-in capability; no custom log rule/workspace prerequisite |
| Nested Azure lab | Host compute, disks, networking/NAT/Bastion, snapshots and retained storage can be substantial; stopped compute does not remove all costs |
| SRE and connected AI services | Verify current billing, region and selected service features |
| Insights/custom logs/metrics/alerts | Review ingestion, retention, query/rule frequency and cardinality |
| Private connectivity/certificates | Endpoints, DNS, vault/storage and lifecycle services can have separate costs |
| Arc/guest services | Review extension, management, storage and related feature charges independently |

Do not infer a whole-stack "free" claim from built-in health alerts or Arc Run
Command. No numeric estimate is promised without a real, owner-approved regional
configuration and current pricing. Set a budget, cost owner, finite session and
targeted cleanup plan before deployment; no cost-producing schedule is supplied.
