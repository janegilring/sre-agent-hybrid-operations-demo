# Future scenario ideas

**NOT IMPLEMENTED / NOT END-TO-END VALIDATED.** These are possible extensions,
not runnable walkthroughs or completed NIC2026 demos. The APP01/HIMDS
stopped-service recovery scenario was not shown at NIC2026.
For available components and their actual limits, use
[attendee readiness](attendee-readiness.md).

## Independent HIMDS recovery

**Signal:** an Arc connectivity alert or stale cloud observation for an exact
guest warrants investigation; it does not prove that HIMDS is stopped.
Distinguish Arc connectivity from AMA Heartbeat, and establish healthy baseline
observations and collection coverage before interpreting missing data.

**Read-only diagnosis:** a separately implemented private path would verify
guest identity, current HIMDS state and bounded redacted diagnostics without
using the affected guest's Arc relay or Run Command. Compare guest and cloud
observations with UTC timestamps; use the
[Arc connectivity troubleshooting guidance](https://learn.microsoft.com/azure/azure-arc/servers/troubleshoot-connectivity)
to distinguish service, network and telemetry causes.

**Proposed action:** only if fresh evidence proves HIMDS is stopped, propose a
fixed, approval-gated **START-only** operation on that guest. No stop, restart,
startup-type change, arbitrary service name or network setter. No HIMDS
custom write tool or workflow is supplied; keep custom writes
disabled until all of these prerequisites are implemented and verified:

- A dedicated noncritical test guest, independently confirmed identity and
  role, and operator rescue access that does not depend on the failed Arc
  path, with an agreed recovery deadline.
- An authenticated private transport and dedicated nonadmin runtime identity
  with narrowly scoped diagnostic and service-start permissions. Separately
  authenticate and restrict MCP execution; the broker receives no human-decision
  receipt and does not independently verify SRE human approval.
- Genuine SRE human approval for the exact proposed target and action. Verify
  effective [Review mode](https://learn.microsoft.com/azure/sre-agent/run-modes)
  plus exact-tool Ask/RequiresApproval, with no matching Allow at any scope,
  Autonomous mode or allowing-hook bypass. Follow the documented
  [tool access policy precedence](https://learn.microsoft.com/azure/sre-agent/tool-access-policies);
  Review alone does not gate every custom tool. A prompt saying "yes" or an
  LLM-generated token is not native approval.
- Fresh post-action guest service state **and** cloud connectivity evidence.
  Report execution, guest recovery, cloud recovery and alert resolution
  separately; missing evidence is Unknown, not permission to retry a write.

The retained [Spooler-only JEA source](../tools/hybrid-service-recovery/README.md)
is a separate offline-tested component, not a HIMDS implementation or permission
to broaden its fixed service boundary. Operator rescue is not SRE remediation.

## Other possible extensions

All ideas below have the same **NOT IMPLEMENTED / NOT END-TO-END VALIDATED**
status. They would require new scoped evidence sources or tool contracts;
existing basic service reads and health/capacity reports do not implement them.

| Idea | Signal and read-only diagnosis | Optional action or key prerequisite |
| --- | --- | --- |
| Broker certificate expiry investigation | An expiry warning or TLS failure; compare the served certificate's validity, identity and chain with the approved binding, without retrieving private keys. | Human-approved renewal/rebinding only through the certificate owner's procedure, with a rollback plan and fresh client verification. |
| Configuration drift investigation | A mismatch with an owner-approved baseline; compare allowlisted nonsecret settings, versions and change records, distinguishing authorized changes from unexplained drift. | An authoritative versioned baseline is required. Propose an exact diff for human review; no automatic rollback or permission widening. |
| Backup freshness verification | An overdue or failed backup record; read scoped job status, protected-object coverage and latest successful recovery-point timestamps. | Approved read access to the actual backup system and an owner-defined freshness policy are required. A recent job is not restore proof; a restore test needs separate approval and an isolated target. |
| Application dependency triage | A failed application health probe; correlate approved endpoint results, dependency status and bounded application logs rather than equating a running Windows service with application health. | An owner-reviewed dependency map and safe probe contract are required. Propose an escalation or separately approved application runbook action, never arbitrary service restarts. |

Any future implementation needs its own permission, acceptance and cleanup
contract. Follow the [safety boundaries](safety-and-reset.md); this page supplies
no executable fault or remediation commands.
