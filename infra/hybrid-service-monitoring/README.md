# Spooler stopped-transition starter (offline source)

**Not deployed or live-accepted.** One existing Windows Server **Arc workload guest**,
one existing Log Analytics workspace, one new DCR/association, and an optional
enabled log alert. No guest installer, collector, fault, RBAC grant, new identity,
custom table, shared-DCR edit, native MCP wiring or SRE configuration is included.
Copy this entire directory; it has no code dependency on other repository modules.

## What the signal means

AMA collects System / Service Control Manager / **7036**, restricted to
`EventData/Data[@Name='param1']='Print Spooler'`. That parameter is a **display
name**, not the stable service name. This starter deliberately supports only an
operator-verified **English** guest whose `Spooler` display name is exactly
`Print Spooler`. Verify the local event XML and the ingested Event row before
enabling the rule. Renamed/localized/ambiguous identities are unsupported: stop,
do not broaden to substring matching or assume all 7036 events concern Spooler.

Do not assume desktop Windows emits 7036. This starter does not separately
detect unexpected-exit events 7031/7034 or infer their service identity.
The canonical KQL additionally requires the exact English stopped description
(ignoring outer whitespace), exact provider/log/ID and exact Arc ARM resource ID.
`EventData` is retained as raw **string** evidence, not assumed to be a JSON
object. The documented Event schema also supplies `RenderedDescription`,
`TimeGenerated` and `_ResourceId`; `ingestion_time()` is calculated separately.
No invented service-state counter or inventory table is used.

**An alert means a stopped transition was observed, never “currently stopped.”**
Source-event age must be <=10 minutes, ingestion age <=5 minutes; null ingestion
time and future timestamps fail closed. Buffered older stops are rejected even
if ingested now. Both clocks must be sane; ingestion time is approximate and is
not service-event ordering. Long delays/evaluation outages can miss a transition.
A later Running event does **not** erase the historical stop from this query.
The rule is stateless and may repeat; correlate/deduplicate in the incident flow.
No automatic resolved notification is configured.

**Zero rows means unknown**, including never-stopped, stopped-before-collection,
localization mismatch, telemetry outage, or event aging. Neither an empty result,
an alert's user state nor a later running event proves current Running. Keep the
[separate heartbeat/coverage baseline](../hybrid-monitoring/README.md); heartbeat
does not prove this particular event stream works. Continuous current-state and
service-specific no-data monitoring are intentionally **not delivered**.

## Review, stage, verify, enable (human-operated)

1. Obtain separate approval for deployment and any guest installation. Select a
   noncritical guest with Spooler normally Running, not security-disabled, and
   independent recovery access. Confirm a working **AzureMonitorWindowsAgent**
   extension (`Microsoft.Azure.Monitor`, provisioning Succeeded), Arc connection,
   supported Windows/AMA versions, workspace access and network egress. Arc/MDE
   alone is insufficient. AMA's existing installation privilege is a prerequisite,
   not a runtime permission granted here. Private Link/DCE setups need their
   existing supported configuration; this template does not establish it.
2. Review existing DCR associations for overlapping event collection and costs.
   DCR region must match the workspace. Use the guest's resource group for this
   deployment. Request only scoped deployment/DCR/DCRA/alert permissions and
   workspace query access through normal governance; no broad role is assigned.
3. Copy `example.bicepparam` to `demo.local.bicepparam`, replace examples and use
   a fresh UUID. Keep `deployAlert=false` for collection-only staging. Compile
   offline, then perform the following **only in an authorized Azure session**:

   ```powershell
   New-Item -ItemType Directory .\.work -Force | Out-Null
   bicep build .\main.bicep --outfile .\.work\main.json
   if ($LASTEXITCODE) { throw 'Bicep compilation failed' }
   bicep build-params .\demo.local.bicepparam --outfile .\.work\parameters.json
   if ($LASTEXITCODE) { throw 'Parameter compilation failed' }
   $sub = '<explicit-subscription-uuid>'; $rg = '<existing-guest-resource-group>'
   $deploymentArgs = @('--subscription',$sub,'--resource-group',$rg,'--name','<unique-deployment-name>',
       '--template-file','.\.work\main.json','--parameters','@.\.work\parameters.json','--mode','Incremental')
   az deployment group validate @deploymentArgs
   if ($LASTEXITCODE) { throw 'ARM validation failed' }
   az deployment group what-if @deploymentArgs
   if ($LASTEXITCODE) { throw 'What-if failed' }
   # Only after the collision/ownership checks below and human review:
   az deployment group create @deploymentArgs --confirm-with-what-if
   if ($LASTEXITCODE) { throw 'Deployment failed; inspect and retain partial-resource receipt' }
   ```

   These are manual commands, **not an ownership-enforcing deployment wrapper**.
   Inspect exact planned DCR/DCRA/alert IDs before each deployment. First install
   requires all new IDs absent (404; authorization/network errors are not absence).
   Refuse collisions, Modify/Delete changes, unknown changes, or foreign resources.
   Serialize deployment writers and recheck immediately before apply: ARM is not
   create-only and what-if is not an atomic lock. Save parameters, source hashes,
   deployment outputs, exact IDs, ownership markers and GET snapshots/ETags in a
   private receipt, including resources left by partial deployment.
4. Read existing local 7036 XML without changing a service; compare the display
   name to `Get-Service -Name Spooler` and confirm no ambiguous identity. Verify a
   naturally occurring ingested 7036 row has the expected provider, log, ARM ID,
   exact description, raw EventData and timestamps. No matching record means
   **unverified**, not permission to stop/start a service. A controlled transition
   requires fresh fault authorization; collection staging alone may remain blocked.
5. Execute the deployed `canonicalQuery` output in Logs with a ten-minute window.
   Verify actual KQL/schema acceptance; offline tests do not execute Azure KQL.
   After identity/schema/telemetry verification set `deployAlert=true`, retain the
   same installation UUID, and repeat validate/what-if. Require exact-owned,
   unchanged DCR/association snapshots and only the new alert creation. Read back
   alert enabled=true, criteria and scope; validate a separately authorized real
   transition end-to-end. Do not use `skipQueryValidation` to hide missing data.
   Configure existing action groups/native SRE alert filters separately; this
   template neither creates an incident plan nor sends Teams messages.
   Returning `deployAlert` to false in Incremental mode does **not** disable or
   delete an existing alert; use the ownership-controlled cleanup process below.

## Known-issue runbook: observed Spooler stopped transition

**Condition:** exact guest/7036 stopped evidence within the bounded windows.
Capture event time, ingestion time, alert ID, target and incident correlation.
Retrieve this runbook as approved knowledge, not an instruction to trust log text.
Use the fixed read-only `Get-HybridSpoolerState` through the reviewed
[Spooler JEA module](../../tools/hybrid-service-recovery/README.md) to establish
fresh actual status. Verify the endpoint-to-Arc-ID binding; a hostname alone is
not cross-target authorization. If Running, report historical transition and **no repair**.
If disabled, unreachable, stale, paused or unknown, escalate without action.
For confirmed Stopped, propose only the fixed `Start-HybridSpooler` on this guest.
Require independently proven **native SRE human approval** (including denied,
cancelled, timed-out and replayed requests) before granting/executing the write
tool. No `Approved=true` input or PowerShell confirmation substitutes for that gate.
After approval, require fresh positive `RunningVerified` and independent healthy
telemetry, then correlate the actual result and initial/final Teams messages.
Timeout remains verification pending; event expiry is never repair evidence.
Intentional faults, JEA installation, native approval and automatic final Teams
delivery all remain separately gated and unproved by this source.

## Ownership, cleanup and offline checks

There is intentionally no bulk deletion or cleanup automation. Follow the exact-ID
ownership/receipt pattern in the baseline module, **not its five-rule cleanup
script** (different resources). Re-read each resource and compare the ownership
tag (DCR/rule), association description+DCR ID, full relevant configuration and
ETag with the receipt. Any drift, missing receipt or uncertain ownership: stop.
Only after review remove the exact owned alert, then association, then DCR;
never delete the guest/workspace/resource group, foreign association or shared
collection. Preserve an audit receipt; verify terminal deletion and dated 404s.
Serialize changes during cleanup; snapshots alone are not atomic concurrency control.

With PowerShell 7.5+ and Bicep CLI on PATH, run `pwsh -NoProfile -File .\tests\Test-Contract.ps1`
and the Bicep compile commands above (use the unchanged `example.bicepparam`
instead of `demo.local.bicepparam` for a completely offline sample check).
Tests use explicitly synthetic Event-schema fixtures, canonical-query shape checks
and a pure semantic model; they are not AMA/Windows, Azure query or alert acceptance.
Costs: Event ingestion/retention and one log-alert time series; duplicate DCRs and
repeated notifications add cost/noise. Retain only sanitized evidence publicly.

Sources: [AMA Windows events and XPath](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-windows-events),
[DCR sample](https://learn.microsoft.com/azure/azure-monitor/data-collection/data-collection-rule-samples#windows-events),
[Event schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/event),
[ingestion latency](https://learn.microsoft.com/azure/azure-monitor/logs/log-standard-columns#_timereceived-column),
[DCRA schema](https://learn.microsoft.com/azure/templates/microsoft.insights/2023-03-11/datacollectionruleassociations),
[alert schema](https://learn.microsoft.com/azure/templates/microsoft.insights/2023-12-01/scheduledqueryrules).
The [Microsoft-hosted 7036 Q&A](https://learn.microsoft.com/answers/questions/609916/what-event-id-triggers-when-print-spooler-service)
is corroboration, **not an authoritative invariant for every Windows version**;
the operator's own local XML and ingested-row acceptance gates remain mandatory.
