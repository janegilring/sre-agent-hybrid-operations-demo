# Public first-party sources

## October 11 neutral skill reference refresh

The current skill export is pinned to source commit
`05304111ec9eb6c237156f68d4a915ae7f99fed8`, blob
`0c512da528e3f8c1b2f3fa64ff4114e48789bc76`. It adds
[Azure/AzureLocal-Supportability](https://github.com/Azure/AzureLocal-Supportability)
beside the five Learn references for dated, applicability-checked TSG/known-issue
research. Community issue status is not confirmation or environment resolution;
unavailable retrieval is UNVERIFIED and no workaround is authorized.
Only this neutral file was refreshed, with CRLF normalization and exact hashes
in the manifest; no companion README, receipt or validator was imported.

## October 11 PowerShell-first follow-up

The [tooling guide](powershell-tooling.md) records the PowerShell 7.5 minimum,
strict JSON behavior and the explicit maintainer-only Azure CLI SDK exception.
Four exported validators/tests are translated derivatives; one regression
runner is narrowly adapted to separate attendee and maintainer invocation.
Their original source path, commit, blob and hash remain in the 93-entry
manifest alongside the new export hash and exact transformation identifier.
The deployed C#/JEA/ARM components are unchanged. The separate neutral skill
refresh above supersedes its previous source pin.

## Earlier October 11 attendee onboarding follow-up

Original attendee procedures now cite Microsoft gMSA/KDS/service-logon guidance,
.NET publish/Windows service and SCM/native-quoting contracts, plus the current
SRE network/MCP, schedule and skill documentation. Exact links and
documentation-versus-live-acceptance limits are in
[guest setup](guest-setup.md#first-party-references),
[broker installation](mcp-service-install.md#sources-and-validation-scope),
[native route/auth reconciliation](mcp-service-install.md#native-sre-connector-is-a-separate-availability-gate),
[schedules](native-reports.md#scheduled-checks-are-separate-from-reports) and
[custom skill import](custom-skill.md).

The neutral skill is one newly authorized committed-source Markdown export at
`908912037636dcfb61ce9593a4f2b9d71ec9df55`; see its exact blob/hashes and the two
README-only attendee adaptations in the current 93-entry manifest. No executable
component, private identity, operator script or source-lab receipt is imported
by this follow-up. The earlier source counts below describe their dated batches.

## October 2 private review refresh

The complete 30-file ordinary-server JEA/MCP dependency set is refreshed from
committed source `9eb5ddfd2fd1058185e2387afdb54d0379c479a3`. Per-file Git blob,
source SHA-256, export SHA-256 and documentation-only sanitization are recorded
in `packaging/source-manifest.json`; the other 62 records preserve prior origins.
New facilitator, guest integration and native-report guides are original kit
documentation, not exported operational receipts.

[Azure Local LENS at d70c577](https://github.com/Azure/AzureLocal-LENS-Workbook/blob/d70c5775701e0372b15d4983e5b6a6b1b20a8a28/README.md)
is a **community-maintained** reference, not an officially supported Microsoft
product. Its retained LAW telemetry and ARG inventory are different data paths.
Link only: no external workbook, DCR, code or license is copied.

The live report's account-specific bindings and the manual collector's fixed
privileged scope are excluded pending a reviewed portable implementation.
See [native recreation and held-source boundaries](native-reports.md).
This was an unpublished review batch; no release or attendee live acceptance.

Retrieved/reviewed 2026-10-01 UTC. Learn source version is the live page on this
date unless a documentation view is specified; those views are not immutable
revisions or installed-release evidence. These links ground original prose,
not copied implementation, live observations or blanket execution authority.

| Source | Scope |
| --- | --- |
| [Azure Local health alerts](https://learn.microsoft.com/en-us/azure/azure-local/manage/health-alerts-via-azure-monitor-alerts?view=azloc-2609) | Built-in AzureEdgeAlerts; no custom rule/Log Analytics prerequisite for these faults |
| [Health Service faults](https://learn.microsoft.com/en-us/azure/azure-local/manage/health-service-faults?view=azloc-2609) | Raw severity, lifecycle, fault identity and catalog |
| [Support tools](https://learn.microsoft.com/en-us/azure/azure-local/manage/support-tools?view=azloc-2609) | Operator/admin collection, import-time update caveat; no execution provided |
| [Azure Local VM management](https://learn.microsoft.com/en-us/azure/azure-local/manage/azure-arc-vm-management-overview?view=azloc-2609) | Lifecycle/Resource Bridge and operation-specific support |
| [Azure Local VM FAQ](https://learn.microsoft.com/en-us/azure/azure-local/manage/azure-arc-vms-faq?view=azloc-2609) | Unmanaged VMs independently Arc-enabled as servers |
| [Arc Run Command](https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command) | Preview guest execution; distinct permissions and result states |
| [Arc security overview](https://learn.microsoft.com/en-us/azure/azure-arc/servers/security-overview) | Service-specific identities and local controls |
| [MCP connectors](https://learn.microsoft.com/en-us/azure/sre-agent/mcp-connectors) | Tool selection, transport/authentication and dynamic exposure |
| [SRE Azure Monitor integration](https://learn.microsoft.com/en-us/azure/sre-agent/azure-monitor-alerts) | Native incident scanner and permissions; not proof of actual routing |
| [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans) | Review mode, matching and overlap |
| [Code Access](https://learn.microsoft.com/en-us/azure/sre-agent/connect-code-service) and [knowledge indexing](https://learn.microsoft.com/en-us/azure/sre-agent/connect-source-code) | Inspect effective authorization; repository selection is not a security boundary |

Official [Health Service faults workbook, pinned commit](https://github.com/Azure-Samples/AzureLocal/blob/c47b91ef5fc732f4c09821b69ff6057ae0a2e35f/health-service-faults/health-service-faults.xlsx):
commit `c47b91ef5fc732f4c09821b69ff6057ae0a2e35f`, blob
`32671b91f0b1d27314bf2a44e5f1433bccc61fdb`; public API identity verified
2026-10-01. Link only, no redistribution. Its metric catalog is not proof of
export/ingestion, and its severity representation must not be silently equated
with the Learn fault-property values or Azure Monitor Sev0-Sev4.

## Microsoft SRE Agent labs and report connectors

Supplied [Microsoft labs branch](https://github.com/microsoft/sre-agent/tree/feature/onboarding-agent-workflows/labs),
reviewed October 2, 2026 at **`1b30297529fcef0411ad64c56e60500a5a3a8e61`**
(September 18). The branch is a mutable preview recipe, not a release; when
reviewed it was 17 commits ahead / 79 behind main. Use the pinned links below
for this reading list; revalidate compatibility before adopting configuration.

| Pinned source | What to learn / limit |
| --- | --- |
| [Scheduled health check and Live Report scenario](https://github.com/microsoft/sre-agent/blob/1b30297529fcef0411ad64c56e60500a5a3a8e61/labs/onboardinglab/README.md#scenario-2-scheduled-health-check-and-live-report) | Report example uses App Insights. Scheduled instructions expressly prohibit updating reports; this is not same-report scheduled-refresh proof. |
| [Log Analytics / App Insights recipe](https://github.com/microsoft/sre-agent/blob/1b30297529fcef0411ad64c56e60500a5a3a8e61/sreagent-templates/recipes/azmon-lawappinsights/README.md) | Candidate recipe inputs: `enableLogAnalyticsConnector`, `lawResourceId`. An example is not permission to deploy. |
| [Connector declarations](https://github.com/microsoft/sre-agent/blob/1b30297529fcef0411ad64c56e60500a5a3a8e61/sreagent-templates/recipes/azmon-lawappinsights/connectors.json) | Native `dataConnectorType: LogAnalytics`, workspace ARM ID and system identity; bind only your approved workspace. |
| [Connector Bicep, lines 40–87](https://github.com/microsoft/sre-agent/blob/1b30297529fcef0411ad64c56e60500a5a3a8e61/sreagent-templates/bicep/agent-extensions.bicep#L40-L87) | Preview `Microsoft.App/agents/connectors@2025-05-01-preview`; verify installed compatibility and permissions separately. |
| [Team onboarding](https://github.com/microsoft/sre-agent/blob/1b30297529fcef0411ad64c56e60500a5a3a8e61/labs/README.md#team-onboarding) | Learning sequence, not a tested whole-lab installer or blanket import instruction. |

The installer discovers healthy LAW/App Insights connectors and
`QueryLogAnalyticsByWorkspaceId` / `QueryAppInsightsUsingAppId` for **subagents**,
not proof of report `allowedTools`. This review establishes no report JSON
schema, widget-provisioning contract or save API.

Read the current [connectors guidance](https://learn.microsoft.com/en-us/azure/sre-agent/connectors)
for built-in LAW querying versus configured connectors; Azure Data Explorer is
distinct from Log Analytics. [Live Reports](https://learn.microsoft.com/en-us/azure/sre-agent/live-reports)
is preview and documents configured connectors, save/gallery and Reload.
Before claiming report acceptance: inspect existing connector health and actual
report-eligible tools, verify narrowly scoped real KQL with timestamps, then
separately authorize one read-only save → gallery → reopen → Reload test.
Account for coverage, unknowns and caching; scheduled output alone is not report
proof. Do not invent `allowedTools` or import autonomous Sev0/Sev1 routing, broad
policies, enabled schedules or email settings from these examples.

**Provenance:** external references only; no Microsoft code, templates or lab
assets are copied or relicensed. These original resource notes do not change
the 92 exported-source records in `packaging/source-manifest.json`. No source-
environment bindings or private research references are included.

## Unresolved title attribution

The exact requested source title **"Power Azure SRE Agent with MCP tools"** was
not recovered by the 2026-10-01 search. It is not cited as an identified source.
The related official blog
[Power Azure SRE Agent with the tools it needs](https://devblogs.microsoft.com/azure-sdk/power-azure-sre-agent-with-connector-namespace/)
was retrieved, but concerns Connector Namespace and is **not claimed to be the
requested article**. This kit does not deploy Connector Namespace or copy that
blog's examples. Retain this unresolved title as a historical research
limitation, not a verified citation. The October 11 approval of public
availability does not identify the missing article or authorize copying it;
any future use requires source verification and the applicable rights review.
