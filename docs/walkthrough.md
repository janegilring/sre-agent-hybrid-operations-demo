# Offline evidence exercises

Optional offline illustration. To build real components, start with the
[starter quickstarts](../README.md), not these synthetic expected outcomes.

**Do not ingest the exercises or answer key into SRE knowledge.**
Every fixture is synthetic; no observation is from a live system.
Use PowerShell 7.5+ from the repository root. No Azure sign-in is needed.

## Understand the evidence boundary

Read the [reference architecture](reference-architecture.md). Distinguish
cloud metadata, native node reads, operator snapshots and guest execution.

An identity result alone does not establish provider access or health.
In a live deployment, caller/execution identity, nonadmin status and correlation
need independent verification. These fixtures do not authenticate to a server.

## Exercise 1: UNKNOWN is a useful result

Run from the repository root:

```powershell
pwsh -NoProfile -File scripts\Invoke-Replay.ps1 -Scenario provider-denied
```

Consider this question while reading the output:

> Why do responding sources not prove complete inventory when another source
> is denied? What can you report without elevating privileges?

Expected: `UNKNOWN`, null count for the denied source, no "zero VMs" statement.
The program is an offline formatter/validator, not an SRE conversation or native
tool replay.

## Exercise 2: empty, missing and stale are different

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

## Exercise 3: management class is not guest access

Use this conceptual matrix, not fabricated environment inventory:

| Lifecycle management | Guest Arc | Valid interpretation |
| --- | --- | --- |
| Managed | Enabled | Separate evidence needed for both; neither proves guest execution |
| Managed | Not enabled | Lifecycle metadata does not by itself establish guest capabilities |
| Unmanaged | Enabled | Guest Arc can exist independently of Azure Local lifecycle management |
| Unmanaged | Not enabled | Approved local evidence may still describe the VM |
| Unknown | Unknown | Missing records/permissions do not classify the object |

Consider:

> Separate lifecycle management, guest Arc, workload/infrastructure role,
> provider visibility and owner evidence. State unknowns. Do not infer class
> from names, absent Azure records or a successful host identity call.

The matrix is conceptual. No lifecycle conversion, guest-agent install
or VM mutation is included.

## Apply the distinction to health alerts

Built-in Azure Local faults use `AzureEdgeAlerts`; a new workspace/custom
alert rule is not a prerequisite. An empty alert list does not prove health.
Native HealthFault denial remains a separate limitation. A metrics catalog is
not export proof. CSS is an operator recommendation, not an agent repair action.

Keep configuration, forwarding, actual alert payload and SRE routing evidence
separate. Do not change a service, node, disk or threshold to manufacture a
result for this exercise.

## Check and reset

Run `pwsh -NoProfile -File tests\Test-Replay.ps1` to check the fixture contracts.
Rerun replay to reset; it creates no cloud resource or service change.
Use [safe reset](safety-and-reset.md) for separately installed components.
The examples are not live reports, benchmarks, fault triggers or remediation.
