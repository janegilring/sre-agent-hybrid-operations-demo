# Recreate native health and capacity reports

**A native recreation guide, not an imported production dashboard.** Replace
angle-bracket placeholders with your reviewed scope before authoring anything.
Report creation does not create a connector, grant access or install collection.
The source environment's report IDs, workspace IDs, tool bindings and volume
GUIDs are deliberately not distributed.

## Prepare a source contract

| View | Source | Required checks / limits |
|---|---|---|
| Node CPU / available RAM / OS disk / heartbeat | Existing scoped Log Analytics `Perf` and `Heartbeat` | Exact node resource IDs; source UTC, freshness and missing-counter coverage. OS CPU is not hypervisor-total CPU; available RAM needs a real denominator before showing usage %. |
| Cluster provider coverage | Bounded nonadmin MCP/JEA | Inspect each provider, not transport completion. Denied HealthFault/Hyper-V means Unknown, never zero faults/VMs. |
| Ordinary guest facts / Spooler / events | Your configured guest MCP/JEA | Exact opaque guest target; sequential calls; System sample ≤3 records/60 minutes; display count/newest time, not raw event messages. No service writes. |
| Current CSV logical capacity | Existing fixed cluster provider | Reconcile the same volume across hosts once; fresh, successful, complete matching inventories. No stable GUID means identity is only cluster + name within a cycle. Partial/conflicting data prevents a complete total. |
| Volume used/total history | Existing SDDC Event 3002, only if already ingested and schema verified | Stable GUIDs, actual observed interval, missing-bucket gaps, comparable capacity samples. Historical and current-volume sets can differ; never join by name or sum both. |
| Updates / Resource Bridge / control-plane inventory | Azure Resource Graph or a separately verified control-plane reader | Exact approved scope and validated tool. An available update is not install readiness or permission. |

Logical volume capacity is **not** physical pool free space, redundancy/repair
reserve or deployable headroom. Observed growth is not a forecast.
Discover existing retained sources first; do not deploy another DCR merely
because a reference workbook lists additional counters.

## Native authoring sequence

1. Open your existing agent → **Live Reports → + New report**.
2. Confirm the displayed eligible tools are the exact read-only tools you
   intended. A subagent tool catalogue is not automatically a report manifest.
3. Use the prompt below with your own scope. Review each requested tool/
   argument; reject write tools or permission expansion.
4. Wait for the report to save in the gallery; record its actual ID/version.
5. Reopen the **current** version and choose **Reload** in an authenticated
   browser. Record source timestamps, coverage, errors and visible chart gaps.
6. Keep native tool proof, UI proof and local synthetic layout tests separate.
   An API returning success is not a browser click or successful provider result.
7. Preserve previous versions; do not overwrite another owner's report. A
   separate capacity tile should not silently replace a health dashboard.

### Health prompt template — configure, review, then authorize

```text
Create a read-only Live Report called "<HEALTH_REPORT_NAME>".
Use only <APPROVED_WORKSPACE_TOOL> scoped to <WORKSPACE_ID> and exact node
resource IDs <NODE_1_RESOURCE_ID>, <NODE_2_RESOURCE_ID>; query the last hour.
Show latest CPU, available RAM, OS disk and heartbeat observations with source
UTC, freshness and required-signal coverage. Missing/stale/denied is Unknown.
Use <APPROVED_CLUSTER_READ_TOOL> only for target <CLUSTER_TARGET>.
Inspect nested provider outcomes; do not infer no faults or zero VMs from denial.
Use <APPROVED_GUEST_READ_TOOLS> sequentially only for <GUEST_TARGET>:
facts, Spooler query, and System events (maximum 3, lookback 60 minutes).
Display event count/newest timestamp, not raw messages.
No write actions, new connectors, permission changes, schedules or privileged
collector. Show the exact proposed tools/arguments for human review before save.
```

### Separate capacity prompt template

```text
Create a separate read-only Live Report called "<CAPACITY_REPORT_NAME>".
Do not modify <EXISTING_HEALTH_REPORT_NAME>.
Use only the approved exact cluster target <CLUSTER_TARGET> and existing
scoped workspace <WORKSPACE_ID>, node IDs <NODE_1_ID>, <NODE_2_ID>.
Reconcile current CSV total/used/free once across fresh matching host
observations. Label it logical CSV capacity, not pool/resilience headroom.
Show 24-hour OS CPU and available-memory trends with 15-minute means.
If schema-verified Event 3002 history exists, use the reviewed GUID allowlist
<VOLUME_GUID_ALLOWLIST>, search at most seven days and plot the actual observed
interval with hourly samples and missing-bucket gaps. Keep historical and
current-volume populations separate. Do not join by name or forecast exhaustion.
Expose source UTC, observation age, coverage and explicit unknowns.
Do not query guests, install collection, add grants, start schedules or invoke
any privileged snapshot collector. Review tools and arguments before saving.
```

These prompts are requirements, **not deterministic deployment templates**.
Review generated code/query/manifest and test denied, partial, empty, stale,
conflicting and malformed inputs before sharing. Never hide source errors
behind a green status. A rendered report is not a health certificate.

## Manual privileged snapshot — deliberately held

The source project has an offline-tested human-admin-per-invocation snapshot
reference. It is unexecuted, not deployed, not a supported production collector,
and not integrated into either report. Its fixed local cluster/domain/node
checks and protected-store dependencies are safety invariants, not sample
strings to replace casually. **Executable collector code is withheld from this
portable batch** pending a reviewed parameterization and offline test pass.
Do not weaken those invariants or attach an elevated identity to dashboard refresh.
A human administrator can bypass a local script; no script constrains that actor.

The lab-bound native report implementation is likewise **not blindly exported**.
This guide provides a supported recreation path; portable deterministic report
source with complete binding validation/tests remains a release gate. No
uncommitted report-owner changes are represented as committed provenance.

## Learn more

- [Live Reports preview](https://learn.microsoft.com/en-us/azure/sre-agent/live-reports):
  current version, Reload, cache behavior, authoring costs and permissions.
- [Pinned Microsoft labs](https://github.com/microsoft/sre-agent/tree/1b30297529fcef0411ad64c56e60500a5a3a8e61/labs):
  preview learning material, not this kit's deployment proof.
- [Pinned Azure Local LENS](https://github.com/Azure/AzureLocal-LENS-Workbook/blob/d70c5775701e0372b15d4983e5b6a6b1b20a8a28/README.md):
  community-maintained, not an officially supported Microsoft product. Use
  source semantics as inspiration; no workbook/DCR/code is redistributed here.
- Scheduled jobs and report Reload are different behaviors. Never claim
  same-persisted-report scheduled refresh from a successful scheduled chat.
