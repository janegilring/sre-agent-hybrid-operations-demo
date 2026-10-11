# Safety, approval and reset

Reviewed 2026-10-01. This is a checklist, not a destructive script.

## Included component cleanup

For the newly documented manual broker installation, use [SCM/artifact/key-ACE
cleanup](mcp-service-install.md#rollback-and-uninstall), then [guest/gMSA teardown](guest-setup.md#scoped-teardown).
No script owns the forest-wide KDS key or shared GPO/certificate infrastructure.
For optional native content, remove only your [skill](custom-skill.md) or
[scheduled task/report](native-reports.md#scheduled-checks-are-separate-from-reports)
after comparing its recorded identity, content and consumers.

Follow the exact receipt/ownership checks in the
[SRE starter](../infra/sre-agent-starter/README.md#iac-interface-powershell-72-installed-bicep-and-azure-cli),
[monitoring baseline](../infra/hybrid-monitoring/README.md#cleanup--partial-deployment),
and [JEA capability](../tools/hybrid-server/README.md#offline-validation-and-teardown).
Preview before applying. These scripts do not delete resource groups, adopt
pre-existing resources, roll back separately owned provider ACLs or clean an
entire LocalBox deployment. Keep private receipts until cleanup is verified.

For [disk collection](../infra/hybrid-monitoring-collection/README.md), cleanup
requires exact resource sets and original configuration fingerprints. Legacy
receipt reconciliation concluded HELD after original snapshots were overwritten.
No resource cleanup was performed or is authorized without fresh owner review;
never construct ownership from current GET responses.
For [Spooler recovery](../tools/hybrid-service-recovery/README.md), cleanup must
verify the owned group, registration, unchanged files and exact service DACL ACE.
Neither cleanup procedure restores service state or authorizes an outage.

The [service-event starter](../infra/hybrid-service-monitoring/README.md#ownership-cleanup-and-offline-checks)
has no automated cleanup wrapper. Verify its receipt and exact DCR, association
and optional alert IDs independently. Never use the five-rule baseline's cleanup
script for these different resources. An event expiring is not service recovery.

The [Arc-connectivity component](../infra/hybrid-arc-connectivity/README.md#manual-preflight-and-application-gate)
has no automatic apply or cleanup. Four selected machines have four separately
owned rules; retain each original full GET and compare configuration before any
separately approved rollback. Do not reuse other components' cleanup scripts.
No live action is authorized by this final packaging closeout.

## Offline reset

The documented `Invoke-Replay.ps1` command reads fixtures and writes stdout only.
No cloud session, service, files or synthetic fault is created by replay. The
offline tests may create and remove their own temporary fixtures; they do not
change a service or cloud resource. Re-run replay to reset the exercise.
If you redirected stdout to a file yourself,
remove only that exact file after reviewing its path; no wildcard cleanup is
required. The supplied code never reads the placeholder binding worksheet.

## Before any separately implemented live demonstration

Record named operator/rollback owner, exact approved targets and exclusions,
action and payload, source/policy versions, pre-state, UTC start/cutoff, cost
and collection budgets, required permissions, independent verification, expected
effects and exact reversal. Require a cleanup reserve and a stop signal.
Missing readiness, role/ownership or rollback evidence is a NO-GO.

No fault action, benchmark or Arc Run Command operation is implemented or
authorized by this kit. The optional fixed Spooler start capability has its
own explicit authorization gates; it is not general guest execution.
A future workload exercise must be bounded and reversible on an identified
noncritical workload only. Exclude cluster nodes, Resource Bridge, unknown-role
objects and unrelated services. Separate collection approval from remediation.

## Targeted live cleanup principles

1. Stop only the demonstration-owned producer/action using its exact identifier.
   Reconcile in-flight work before deciding whether another attempt is safe.
2. Restore only the approved changed setting/service to its captured pre-state.
   Verify actual workload health rather than assuming a successful API return
   means recovery. If reversal fails, stop other work and escalate.
3. Remove only newly owned temporary command resources, assignments, rules or
   schedules after verifying identity/ownership and dependencies. Preserve
   pre-existing commands, role assignments, integrations and owner monitoring.
4. Verify removal/restoration independently. Deleting a command resource does
   not undo script effects; removing a role does not prove instant token
   revocation. Record these limitations.
5. Retain approved audit records and timestamps in a private evidence store.
   Do not erase agent history, unrelated incidents, knowledge or logs to make
   a demonstration look clean.
6. Report what was restored, what was never changed and what remains uncertain.
   Incident resolution/acknowledgment and Teams messages are separate approved
   writes, not automatic consequences of a read-only investigation.

Never delete an entire resource group or broad directory as a shortcut. Do not
disable existing Health alerts/Insights, remove Resource Bridge, reset shared
connectors, purge knowledge or widen runtime privileges as a "demo reset."
