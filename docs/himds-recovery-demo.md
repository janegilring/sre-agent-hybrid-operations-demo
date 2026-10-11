# Independent HIMDS recovery: scenario and acceptance gates

This design checklist explains why a recovery channel must not depend on
the component being repaired. **No HIMDS executor or end-to-end repair is
provided.** Use it to evaluate an independently implemented recovery path;
keep custom writes disabled until the approval and recovery checks below pass.

[Windows PowerShell 5.1 documents `Register-PSSessionConfiguration -NoServiceRestart` as not implemented](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/register-pssessionconfiguration?view=powershell-5.1#-noservicerestart).
Passing that switch alone does not guarantee preservation of WinRM.
Endpoint registration needs a separately reviewed maintenance window and
recovery access; this checklist supplies no registration or repair commands.

## Intended flow

```text
Azure Monitor exact guest alert
  -> SRE Agent filtered incident investigation
  -> private VNet MCP backend
  -> guest private IP / constrained Windows remoting
  -> HIMDS state and bounded redacted diagnostics
  -> authenticated human approval
  -> start only HIMDS
  -> local state, fresh Arc connectivity, alert resolution
```

Limit any separately implemented validation to dedicated test guests.
DNS, VLAN and host/management-network changes are outside this scenario.
HIMDS is the Azure Connected Machine Agent's local identity service.
The private diagnostic/recovery channel must not use the affected guest's
Arc relay or Run Command.

## Prerequisites and boundaries

| Boundary | Required acceptance |
|---|---|
| Targets | Independently verified guest identity, private address and role. Never target a resource bridge, cluster node or management machine by inference. |
| Baseline | Known healthy HIMDS and Arc observations for comparison, with timestamps. |
| Transport | Authorized private MCP caller and constrained guest session; an administrator setup shell is not runtime acceptance. |
| Runtime | Dedicated nonadmin account, least-privilege JEA capability and protected credential custody. No bootstrap credential exposed to SRE. |
| Diagnosis | Bounded service state and redacted logs; no arbitrary script, command, path or service name. |
| Write gate | Executor verifies approval actor, target, operation, request, expiry and single use. An LLM-generated token or a prompt saying "yes" is not approval. |
| Recovery | Start only HIMDS; no stop, restart, startup-type, DNS, adapter or firewall setters. |
| Alert | Exact target binding and healthy baseline, measured missing-signal detection, duplicate-investigation safeguards. |
| Rescue | Operator has independent local/RDP access and a fixed recovery deadline. |
| Existing services | Existing identities, listeners, settings, schedules and reports remain intact. |

Native SRE tool approval, external MCP-client approval and downstream executor
authorization are separate controls. If their trusted binding is not verified,
keep custom writes disabled and demonstrate diagnosis/proposed repair instead.
Do not present operator rescue as SRE remediation.

## Transport tradeoff

Windows Negotiate/NTLM can encrypt messages over HTTP. For workgroup targets,
this does not provide authenticated server identity; TrustedHosts suppresses
the identity check rather than establishing trust. Exact reviewed targets,
private routing, encrypted messages and a constrained endpoint are necessary
lab boundaries, not equivalent to authenticated TLS.

Do not replace machine-wide TrustedHosts or reconfigure shared listeners
without reviewing active and dormant consumers. Production deployments should
use an independently trusted transport and organizational credential policy.
This guide does not authorize installing a new root certificate, broadening
permissions or weakening authentication.

## Alert timing and missing data

Arc disconnection detection can take approximately 15-30 minutes, followed by
evaluation and delivery latency. Measure it in your environment before relying
on a detection or recovery deadline.

AMA Heartbeat and Arc connectivity are distinct signals. If AMA was never
collecting from a guest, a missing-AMA-heartbeat rule is not a valid HIMDS fault
detector. Establish positive telemetry coverage before enabling absence rules.
Existing Resource Health rules and incident routes must not be duplicated.

## Sample prompts

These require your own verified read tools and, for repair, an independently
approved executor. They do not install capabilities or authorize a fault.

**Read only**

> Investigate the current Arc alert for `<GUEST>` only. Use the independent
> private MCP path to read HIMDS state and bounded redacted diagnostics.
> Do not use the guest's Arc channel for commands. Distinguish telemetry loss
> from proven service, network or VM failure. Cite UTC observation times and
> make no changes.

**Propose**

> If independent current evidence proves HIMDS is stopped, propose starting
> only HIMDS on `<GUEST>`. Show the exact action and verification steps.
> Request authenticated human approval. Do not execute until the executor has
> accepted that approval; do not change any other service or setting.

**Verify**

> Read back HIMDS state through the private path and check for a new Arc
> observation after the action. Report execution, local recovery, cloud
> connectivity, alert resolution and incident closure separately. Missing
> evidence is Unknown, not permission to retry a write.

## Implementation limits

Native approval delivery to a custom executor is not implemented here.
Writes must remain disabled without a verified trusted binding. Require a
fresh target-bound approval for every guest; never reuse an earlier approval.

For existing component setup and safer fallback exercises, see
[setup](setup.md), [guest setup](guest-setup.md),
[offline exercises](walkthrough.md), and [safety/reset](safety-and-reset.md).
The [external MCP-client bonus](sre-agent-mcp-client-bonus-demo.md) uses the
opposite direction and does not bypass these approval boundaries.
