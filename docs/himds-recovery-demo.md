# Independent HIMDS recovery: scenario and acceptance gates

**October 10, 2026: preparation, not an accepted end-to-end repair.**
This optional scenario demonstrates why the recovery channel must not depend
on the component being repaired. It is separate from the recorded alert and
local offline application exercises.

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

Use two dedicated workgroup test guests if desired. Both use stopped HIMDS;
invalid DNS, VLAN changes and host/management-network faults are excluded.
HIMDS is the Azure Connected Machine Agent's local identity service.
The private diagnostic/recovery channel must not use the affected guest's
Arc relay or Run Command.

## Prerequisites and boundaries

| Boundary | Required acceptance |
|---|---|
| Targets | Independently verified guest identity, private address and role. Never target a resource bridge, cluster node or management machine by inference. |
| Baseline | Current HIMDS Running and fresh Arc observation before arming a fault. |
| Transport | Authorized private MCP caller and constrained guest session; an administrator setup shell is not runtime acceptance. |
| Runtime | Dedicated nonadmin account, least-privilege JEA capability and protected credential custody. No bootstrap credential exposed to SRE. |
| Diagnosis | Bounded service state and redacted logs; no arbitrary script, command, path or service name. |
| Write gate | Executor verifies approval actor, target, operation, request, expiry and single use. An LLM-generated token or a prompt saying "yes" is not approval. |
| Recovery | Start only HIMDS; no stop, restart, startup-type, DNS, adapter or firewall setters. |
| Alert | Exact target binding and healthy baseline, measured missing-signal detection, duplicate-investigation safeguards. |
| Rescue | Presenter has independent local/RDP access and a fixed recovery deadline. |
| Other demos | Existing identities, listeners, settings, schedules and reports remain intact. |

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
evaluation and delivery latency. Measure it in your environment before placing
it in a short live slot.

AMA Heartbeat and Arc connectivity are distinct signals. If AMA was never
collecting from a guest, a missing-AMA-heartbeat rule is not a valid HIMDS fault
detector. Establish positive telemetry coverage before enabling absence rules.
Existing Resource Health rules and incident routes must not be duplicated.

## Presenter sequence

Do not execute this sequence until all gates above are accepted.

1. Privately verify the exact guest and current baseline. Prepare a local
   rescue console and deadline.
2. Presenter alone stops HIMDS locally. Do not expose a fault tool to SRE and
   do not stop other Arc services or change startup type.
3. Observe the real Azure alert and its native incident. A direct chat is not
   evidence of alert ingestion.
4. Ask for private diagnosis without writes; inspect timestamps and unknowns.
5. Review the proposed start-only action and approve its exact pending
   invocation through the verified approval mechanism.
6. Inspect executor audit, local Running state and first fresh Arc observation.
   Alert resolution and incident closure are separate verification steps.
7. If the deadline is reached, perform local operator rescue. Label the
   outcome honestly and do not repeat the fault for a better recording.

For a second guest, require a new target-bound approval. Never reuse the first
guest's approval or broaden the operation.

## Sample prompts

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

## Current publication status

This is a portable scenario and safety checklist, not an installed recovery
module or proof of a successful fault rehearsal. Native approval delivery to
the custom executor is unverified; writes must remain disabled without that
binding. No intentional guest fault has been performed during preparation.

For existing component setup and safer fallback exercises, see
[setup](setup.md), [guest setup](guest-setup.md),
[practice](practice.md), and [safety/reset](safety-and-reset.md).
The [external MCP-client bonus](sre-agent-mcp-client-bonus-demo.md) uses the
opposite direction and does not bypass these approval boundaries.
