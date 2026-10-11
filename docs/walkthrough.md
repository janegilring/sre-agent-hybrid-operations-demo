# Presenter walkthrough and answer key

Optional offline illustration. To build real components, start with the
[starter quickstarts](../README.md), not these synthetic expected outcomes.

**Presenter-only. Do not ingest into SRE knowledge.**
Reviewed 2026-10-01. Every fixture is synthetic; no observation is from a live
system. Prompts below are prepared examples, not requests already executed.

## Segment 1: establish the evidence boundary

Explain the [reference architecture](reference-architecture.md). Distinguish
cloud metadata, native node reads, operator snapshots and guest execution.

Prepared live prompt, **only after separate live approval and implementation**:

> Use only the deployed, approved identity tools for the fixed approved targets.
> Report observed target and correlation. Distinguish returned fields from
> independently verified caller/execution identity, nonadmin status and time.
> Do not call other tools or change state.

Expected: identity-only evidence and explicit missing audit fields, not invented
proof from agent narration. Stop if tool/schema/scope or independent audit is
unavailable. Offline fallback: discuss the boundary; no synthetic identity is
passed off as an actual authenticated call.

## Segment 2: UNKNOWN is a useful result

Run from the repository root:

```powershell
pwsh -NoProfile -File scripts\Invoke-Replay.ps1 -Scenario provider-denied
```

Prepared evidence-review prompt:

> This is synthetic teaching data. Explain why responding sources do not prove
> complete inventory. Preserve the denied source and unknown count. Recommend
> an approval-gated next step, not elevation or another privileged transport.

Expected: `UNKNOWN`, null count for the denied source, no "zero VMs" statement.
The program is an offline formatter/validator, not an SRE conversation or native
tool replay. Do not upload presenter answer keys to the investigating agent.

## Segment 3: empty, missing and stale are different

```powershell
pwsh -NoProfile -File scripts\Invoke-Replay.ps1 -Scenario all
```

| Synthetic case | Expected computed result | Point to explain |
| --- | --- | --- |
| `provider-denied` | `UNKNOWN` | A responding node can deny its provider; denied count stays null |
| `complete-empty` | `NO_RESULTS_RETURNED` | Complete successful empty source/window is not global health |
| `missing-source` | `UNKNOWN` | Absent required scope cannot be inferred from observed rows |
| `stale-source` | `UNKNOWN` | Historical data is not refreshed by presenting it now |
| `observed-results` | `RESULTS_OBSERVED` | Report scoped rows without inventing root cause or severity conversion |
| `partial-source` | `UNKNOWN` | Returned rows may be a lower bound, not exhaustive inventory |

The fixture reference clock and freshness policy are explicit and deterministic.
Do not compare fixtures against today's clock and then claim live freshness.
No numeric Health Service-to-Azure Monitor severity mapping is implemented.

Fallback if PowerShell 7.5+ is unavailable: show the
[checked-in fixture and expected labels](../examples/scenarios.json) as a static
synthetic example. Do not describe that as an executed test or a recording.

## Segment 4: management class is not guest access

Use this conceptual matrix, not fabricated environment inventory:

| Lifecycle management | Guest Arc | Valid interpretation |
| --- | --- | --- |
| Managed | Enabled | Separate evidence needed for both; neither proves guest execution |
| Managed | Not enabled | Lifecycle metadata does not by itself establish guest capabilities |
| Unmanaged | Enabled | Guest Arc can exist independently of Azure Local lifecycle management |
| Unmanaged | Not enabled | Approved local evidence may still describe the VM |
| Unknown | Unknown | Missing records/permissions do not classify the object |

Prepared prompt:

> Separate lifecycle management, guest Arc, workload/infrastructure role,
> provider visibility and owner evidence. State unknowns. Do not infer class
> from names, absent Azure records or a successful host identity call.

Fallback: explain the matrix only. No lifecycle conversion, guest-agent install
or VM mutation is included.

## Segment 5: existing health alerts and operator escalation

Prepared live read-only prompt, subject to authorized tools and scope:

> Read the existing approved cluster's Azure Monitor health-alert evidence.
> Preserve raw severity and source time. Distinguish configuration, forwarding,
> actual alert payload and SRE routing. If coverage is incomplete, explain the
> gap and recommend operator-reviewed diagnostics without executing them.

Expected: reuse existing `AzureEdgeAlerts`, no new workspace/custom alert-rule
prerequisite for built-in faults, no claim that an empty alert list proves health.
Native HealthFault denial remains a separate limitation. A metrics catalog is
not export proof. CSS is an operator recommendation, not an agent repair action.

If no live alert/routing proof exists, explain the sourced product behavior as
reference architecture. Do not cause a node outage, remove a disk, lower a
threshold or stop Resource Bridge to manufacture a result.

## Close and reset

Summarize what was actually executed offline versus anything separately proved
live, with dates and remaining coverage. Use [safe reset](safety-and-reset.md).
This release contains no recorded live report or video, no benchmark result,
no fault trigger and no automatic remediation. Those remain separate gated work.
