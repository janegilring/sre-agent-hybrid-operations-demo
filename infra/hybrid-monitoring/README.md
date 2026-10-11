# Windows hybrid monitoring baseline

Reusable source implementation; **not a claim of deployed monitoring**.
Five persistent Azure Monitor scheduled log rules: AMA heartbeat missing,
CPU high, physical memory available low, logical disk free low, and missing
required performance-counter coverage. Enabled defaults to **true**.
No SRE agent, connector, role assignment, guest extension, DCR, service collector,
action group, or resource group is created or modified.

## Pick the components

- Use `main.bicep` for the five-rule baseline over **one existing workspace**.
  `queries/*.kql` are the canonical source loaded directly by Bicep and scripts.
- Use `Preflight.ps1` alone to check existing Windows collection.
- Use the private MCP/JEA components separately for on-demand ordinary-server
  reads. They do not require this monitoring module.
- For these alerts, each server must already send AMA Windows Heartbeat/Perf
  with an ARM `_ResourceId` (Arc-enabled server or Azure VM). An ordinary
  non-Arc Windows host is **not** silently supported by substituting computer
  names; onboard to a supported AMA path separately or supply a separately
  designed custom collector. LocalBox is optional.

Direct resource declarations are intentional: this small module needs exact
query ingestion, dimensional contracts and ownership tags; no registry module
or package installation is needed. API `2023-12-01` is pinned.

## Collection and inventory prerequisites

Supply explicit full ARM IDs; there is **no scan-all fallback**. Copy
`targets.example.json` and `config.example.json` to private `*.local.json`
files, replacing placeholders. Keep receipts and actual bindings private.
One subscription/workspace per invocation; 1–50 unique targets.

Every target must have:

| Signal | Windows counter / requirement |
|---|---|
| AMA heartbeat | `Heartbeat`, Category `Azure Monitor Agent`, OSType Windows |
| CPU | `\Processor(_Total)\% Processor Time` (already 0–100 percent, **not** a 0–1 fraction) |
| Physical memory | `\Memory\Available Bytes` by default, or set `memoryCounter` to `Available MBytes` for every target |
| Disk | `\LogicalDisk(*)\% Free Space`, explicit required instances in `disks`, e.g. `C:` and `D:`; `_Total` excluded |

Configure a Windows-only DCR separately to send `Microsoft-Perf` to the chosen
Log Analytics workspace. A 60-second or faster sample interval supports the
default minimum three samples in each five-minute bin. Existing collection is
never replaced by these scripts. Wait for a complete sustained window and
ingestion lag before preflight. Verify DCR associations/destination, table
availability and actual exact counter/instance spelling, not only extension
installation success. Counter localization/unsupported counters can block
coverage; don't alias unverified counters.

`totalMemoryMiB` is **physical usable RAM**, verified from the guest/approved
inventory before deployment. Available Bytes / 1,048,576 divided by this value
gives available physical-memory percent. Revalidate after resizing/hot-add.
Windows `% Committed Bytes In Use` measures commit limit, not physical free
RAM; `100 - committed percent` is not a substitute. There is no assumed
default `% Available Memory` counter. Missing configured memory counter,
invalid capacity or missing required disk fails preflight rather than skipping.

## Query and alert semantics

| Rule | Default condition | Severity |
|---|---|---|
| heartbeat | No fresh AMA heartbeat for 10 minutes | 2 |
| cpu | **Every** closed five-minute bin average >90%, across 15 minutes | 2 |
| memory | Every closed bin average physical available <10%, across 15 minutes | 2 |
| disk | Every closed bin average free <10%, per required disk, across 15 minutes | 2 |
| coverage | Required CPU/memory/disk series missing, stale, invalid or insufficiently sampled | 3 |

Threshold equality does not breach. Rules evaluate every five minutes by
default. CPU uses the **minimum** bin average; low-memory/disk use the
**maximum**, not an instantaneous minimum or cross-disk/host average.
Only complete bins ending before `bin(now() - ingestionLag, 5m)` are used.
Defaults allow two minutes ingestion lag; data and freshness scans are bounded
to an hour by the rule. Configure frequency 5/10/15 minutes, sustained 15/30
minutes, freshness 5–30, lag 0–10, and recovery 5/10/15. Validate actual API
acceptance using deployment preview before apply, then verify actual provider
acceptance and effective settings after apply; preview alone is not proof.

Heartbeat and counter coverage start with expected inventory and **left outer
join** bounded observations. Never-seen targets, no recent rows and whole-set
disappearance therefore produce missing rows with `Value=1`, including when
all targets disappear simultaneously. IDs and disk instances are normalized
case-insensitively. Synthetic result `TimeGenerated=now()` avoids losing these
rows to the alert evaluation time filter. Missing tables/query failures remain
errors (no fuzzy-union success fallback).

All alerts split by resource, instance and signal; the payload's resource ID
is the actual host ARM ID. `resolveConfiguration.autoResolved=true` and
`resolveConfiguration.timeToResolve=PT10M` request ten healthy minutes before
resolution by default (`recoveryMinutes` is configurable). `autoMitigate` is
deliberately omitted: the resource provider rejects it alongside
`resolveConfiguration`, even when ARM validate and what-if pass. The API schema
lists both properties but does not express this runtime constraint. Validation
requires the explicit recovery configuration; an absent, null or defaulted
`autoMitigate` in a GET response does not replace that contract. **Monitor resolving
a performance alert is not proof of guest recovery:** loss of Perf can remove
that series and must be treated as unknown while coverage/heartbeat is bad.
Confirm fresh positive samples and current guest condition independently.
Heartbeat loss means telemetry loss, **not** power outage, Arc Disconnected,
network diagnosis or service stopped.

## Prepare, preview, apply, verify

### Running the complete query in Azure Logs

Use KQL mode in the alert's configured workspace. Copy the **entire deployed**
`properties.criteria.allOf[0].query` into a dedicated query tab. Focus the
editor, press **Ctrl+A**, then **Run** (or **Shift+Enter**). Include the final
tabular expression after the `let` declarations; declarations alone do not
return a table.

Log Analytics uses blank lines to separate the current query when running
without an explicit selection. Running only a block of `let` declarations can
produce **“No tabular expression statement found”** even when the complete query
is valid. The generator trims file boundaries before joining with one newline.
If selecting everything still fails, retain the complete submitted text and
error/correlation ID for diagnosis. Obtain separate approval for any live
query update. Full-query execution does not prove alert firing,
incident routing, Teams delivery, or overall host health.

See [Microsoft's Log Analytics tutorial](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-tutorial#visualize-query-results-as-charts)
for the editor's blank-line/current-query behavior.

PowerShell 7.2+, Azure CLI and Bicep CLI are required. Authenticate separately
beforehand. Scripts do not login, change default subscription or install
extensions. REST queries avoid the optional CLI Log Analytics extension.
Run from the repository; no private values are required in checked-in files.

```powershell
$scope = @{
  SubscriptionId = '<subscription UUID>'
  WorkspaceResourceId = '<full workspace ARM ID>'
  TargetsPath = '.\infra\hybrid-monitoring\targets.local.json'
  ConfigPath = '.\infra\hybrid-monitoring\config.local.json'
}
.\infra\hybrid-monitoring\Preflight.ps1 @scope
$deployment = @{
  ResourceGroup = '<existing alert resource group>'
  ReceiptPath = '.\infra\hybrid-monitoring\ownership.local.json'
}
# Read-only telemetry, compile, ARM validate, then displayed ARM what-if.
.\infra\hybrid-monitoring\Deploy.ps1 @scope @deployment
# Separate owner approval is required before this command:
.\infra\hybrid-monitoring\Deploy.ps1 @scope @deployment -Apply -Confirm
.\infra\hybrid-monitoring\Validate.ps1 @scope @deployment
```

Coverage failure terminates nonzero before Azure writes. Authentication,
authorization, partial-query and API errors are never converted to success.
All canonical queries execute in preflight. Deployment is incremental, with
no broad target discovery or RG creation. `-Apply` plus ShouldProcess
confirmation is mandatory for writes (`-WhatIf` never creates rules).
Disabled configuration can be previewed/applied for deliberate staging,
but **Validate fails disabled rules: disabled is not delivery**.
Full Azure policy/RBAC/ARM validation is a separate live gate; local compile
and tests do not claim that it passed.

The deployment refuses **any existing rule with these five names**, including
prior owned installs, and never overwrites an existing receipt. Choose a
unique prefix. Run operators serially; ARM deployments have no atomic
create-only precondition, so a concurrent creator could race the final check.
This initial installer intentionally does not automate upgrades/adoption.

## Permissions, cost and maintenance

The operator needs workspace query permissions (including Heartbeat and Perf),
resource read, ARM deployment validate/what-if/write, and scoped
`Microsoft.Insights/scheduledQueryRules/read/write/delete` for apply/cleanup.
Reader alone cannot deploy. Use separately approved scoped roles, not automatic
subscription-wide grants. Query-time access for the log rule must be supported
by the workspace access mode and deploying identity; private-link/network and
table restrictions must be checked. No managed identity or broad RBAC is
provisioned here.

Costs include five log alert rules, evaluated dimensional time series and
queries, plus existing/new Perf ingestion and retention. Per-disk splitting
increases series count; faster DCR sampling increases ingestion. Check current
Azure Monitor pricing for the selected region; no fixed free-cost claim.

For maintenance, use a separately approved, time-bounded Azure Monitor alert
processing rule scoped to these exact IDs to suppress **actions**, retaining
evaluation. Native SRE intake may not honor action-group suppression: coordinate
the matching native response-plan filter separately and verify its behavior.
If evaluation must stop, explicitly disable only owned rule IDs in the portal,
record the change, then re-enable and rerun preflight/validation. Do not delete
targets from inventory merely to hide outages. Never call absence “recovered.”
For reviewed query/config changes, export existing owned settings first;
this initial installer requires owned cleanup and redeployment (monitoring
gap acknowledged), or an explicitly reviewed manual update, not silent overwrite.

## Cleanup / partial deployment

```powershell
.\infra\hybrid-monitoring\Cleanup.ps1 -SubscriptionId '<UUID>' `
  -ResourceGroup '<alert RG>' -ReceiptPath '.\infra\hybrid-monitoring\ownership.local.json' -WhatIf
# After reviewing exact IDs:
.\infra\hybrid-monitoring\Cleanup.ps1 -SubscriptionId '<UUID>' `
  -ResourceGroup '<alert RG>' -ReceiptPath '.\infra\hybrid-monitoring\ownership.local.json' -Confirm
```

Receipt records the exact **observed created IDs** and unique ownership tag.
Partial creation is reconciled in `finally`; cleanup checks scope and live tags,
deletes only those IDs, and verifies absence. No RG, workspace, DCR, extension,
existing canary or prior monitoring is deleted. Keep the receipt for audit.
If the reconciliation read fails, the receipt remains `applying`; cleanup
refuses it. An operator must inspect each exact `plannedRuleIds` resource,
verify the unique token and record only actually created IDs as `partial`
before retrying. Never infer ownership from names alone.

## Explicit gaps and native SRE handoff

- **Arc connection-status alert is separate.** Use the
  [per-machine Arc transition component](../hybrid-arc-connectivity/README.md)
  for Available -> Unavailable events. ARM connection state is not the AMA
  Heartbeat table. Do not paste an ARG `Resources` query into these log rules.
- **Current service-state alert is not implemented.** AMA does not provide
  Spooler state by default. A reviewed collector/schema must report explicit
  state, resource, observation time and missing-data coverage. Recovery needs
  a fresh positive `Running` observation, not a stop event aging out. The
  [service-event starter](../hybrid-service-monitoring/README.md) observes a
  historical transition, not current state.
- **Native incident routing is separate.** Retain existing managed-resource
  scope and Teams connector. Add only owner-approved alert/target scope,
  configure native Azure Monitor response-plan matching against the **actual
  five rule names, actual alert target IDs, severities 2/3 and intended fired
  state** using supported UI fields, and avoid broad prefix/catch-all overlaps.
  Do not fabricate a webhook/action-group bridge or assume log-rule creation
  activates SRE. Start in Review mode with read-only triage/runbook instructions.
  Prove a fresh Monitor alert → native incident → initial Teams → positive
  recovery → final Teams separately; validate payload/filter semantics and
  resolved-event behavior before claiming automatic closure. No fault is
  authorized by this module.

## Tests

```powershell
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Queries.ps1
.\infra\hybrid-monitoring\tests\Test-Scripts.ps1
.\infra\hybrid-monitoring\tests\Test-Template.ps1
az bicep build --file infra\hybrid-monitoring\main.bicep --stdout | Out-Null
```

The PowerShell 7.5+ reference-model tests cover inventory all-absent/never-seen/stale/mixed-case behavior,
sustained CPU units, separate disks, memory conversion and query contracts.
PowerShell tests parse scripts and exercise exact-coverage failures, rendering,
CLI-error handling, receipt scope, preview/WhatIf nonmutation, and rejection
of foreign deployment/cleanup ownership. Mock GET tests also cover optional
`autoMitigate`, required recovery settings and unchanged enabled/name/scope/ownership
checks. The local compiled-template test verifies the shared five-rule loop,
exclusive recovery properties and the ten-minute default. These are reference/contract tests, not
a Kusto emulator. Preflight is the required real KQL/collection test.

## First-party references (reviewed October 1, 2026)

- [ScheduledQueryRules schema](https://learn.microsoft.com/azure/templates/microsoft.insights/2023-12-01/scheduledqueryrules)
- [Create log alerts](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-create-log-alert-rule)
- [Windows performance collection](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-performance)
- [AMA heartbeat verification](https://learn.microsoft.com/azure/azure-monitor/agents/azure-monitor-agent-manage#verify-installation)
- [Query time bounds](https://learn.microsoft.com/azure/azure-monitor/logs/query-optimization#time-span-of-the-processed-query)
- [Arc site monitoring limits](https://learn.microsoft.com/azure/azure-arc/site-manager/how-to-configure-monitor-site)
- [PowerShell ShouldProcess](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-shouldprocess)
