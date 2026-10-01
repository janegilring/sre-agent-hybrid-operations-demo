# Safety, approval and reset

Reviewed 2026-10-01. This is a checklist, not a destructive script.

## Offline reset

The documented `python -B` commands read fixtures and write stdout only.
No cloud session, service, files or synthetic fault is created. Re-run the
commands to reset the exercise. If you redirected stdout to a file yourself,
remove only that exact file after reviewing its path; no wildcard cleanup is
required. The supplied code never reads the placeholder binding worksheet.

## Before any separately implemented live demonstration

Record named operator/rollback owner, exact approved targets and exclusions,
action and payload, source/policy versions, pre-state, UTC start/cutoff, cost
and collection budgets, required permissions, independent verification, expected
effects and exact reversal. Require a cleanup reserve and a stop signal.
Missing readiness, role/ownership or rollback evidence is a NO-GO.

No fault action, benchmark or guest command is implemented or authorized by this
kit. A future workload exercise must be bounded and reversible on an identified
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
