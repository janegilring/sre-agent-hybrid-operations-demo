# Reference architecture

Reference design only; baseline reviewed 2026-10-01, attendee wording updated
2026-10-11. The [conceptual SVG](diagrams/nic2026-demo-environment.svg) is included;
deployed bindings are not. Sources: [source register](sources.md).

For executable pieces see the [starter component table](../README.md).
The ordinary Windows path is domain Kerberos + bounded JEA, optionally exposed
through a separately accepted MCP host; it does not require Arc or Azure Local.
The monitoring path is different: supported AMA Heartbeat/Perf collection with
ARM target IDs is required. Portable MCP source is included, while actual host
deployment, guest reachability and native-agent acceptance remain separate gates.

| Boundary | Flow and purpose |
| --- | --- |
| Built-in health alerts | Azure Local Health Service -> AzureEdgeAlerts -> Azure Monitor; existing health-fault transport, not a custom log collector |
| Observability | Existing Insights/logs/metrics -> authorized queries; actual export/ingestion must be proved |
| Optional Spooler transition | Existing AMA -> scoped English SCM 7036 collection -> bounded stopped-transition rule; zero events is UNKNOWN, not a current-state signal |
| Arc connectivity transition | Resource Health Available → Unavailable -> one activity-log rule per exact machine ID; independent of AMA and not current-state inventory |
| Bounded node diagnostics | SRE identity -> approved private HTTPS MCP -> nonadmin service -> explicit Kerberos/WinRM JEA -> fixed node/provider reads |
| Guest execution | Azure control plane -> Connected Machine agent -> separately approved guest operation; not the private node path |
| Knowledge | Restricted read-only retrieval of neutral runbooks; presenter answers and bindings excluded |
| Notification | Separately approved incident/notification integration; audience, status writes and cleanup reviewed |

The MCP design must reject arbitrary scripts, credentials, node lists and remote
sessions. Authentication, tool visibility, JEA command exposure and actual
provider authorization are separate checks. Identity proof is not complete
health or VM inventory proof. An installed module is not permission to use it.

The Arc path does not need direct RDP/SSH for Run Command, but still needs agent
connectivity, authorized operations and local policy support. Preview status
and actual execution identity require review. It must not be used as a provider
denial workaround.

## Evidence and classification

Keep Azure metadata, native provider observations and operator snapshots
separately attributed with original UTC times and independent audit correlation.
Never replace failed native data with an operator success or a synthetic fixture.

For each VM, record role, Azure Local lifecycle-managed/unmanaged status and
guest Arc status independently. Local-only lifecycle management can be deliberate;
guest Arc may still be enabled. Names and missing Azure resources do not establish
classification or identity correlation. Keep provider visibility, owner and
power observations separate.

Resource Bridge, cluster nodes and unknown-role objects remain excluded from
workload fault/repair testing, while accounted for in approved inventory.
Do not filter them away to claim complete coverage.

## Content isolation

The neutral runbooks repository explains diagnosis but contains no staged causes
or expected demonstration answers. This private repository contains those answers
and must not be available to the investigating agent through indexing, broad
GitHub tools or inherited connectors. Prompt instructions are not access control.
Public release of either repository requires separate owner approval; do not
make a repository public to solve connector authentication.
