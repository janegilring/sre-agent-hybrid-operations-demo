# Practise the hybrid operations story

**Facilitator guide · 60 minutes · no reserved Q&A.** Use your own
approved lab and evidence. This is not proof that this kit provisions a complete
environment. Prepare a ten-minute preflight before the session clock.

## Preflight — ten minutes, not counted

Open your introductory material, existing agent, knowledge/runbook, connector
tool list, Monitor alert rules, reviewed incident/Teams evidence, completed
scheduled-task history and native report gallery. Confirm tenant/identity,
target allowlists, source times and private screen sharing. Choose LIVE,
RECORDED or SIMULATED for each segment. Never improvise a service fault.

## Run of show

| Clock | Minutes | Do | Say / expected evidence |
|---|---:|---|---|
| 00–06 | 6 | Introduce SRE Agent generally, then private-server operations. | “An alert gives us a symptom. Reviewed knowledge and bounded tools help us decide what is safe.” Arc/Azure Local are optional, not prerequisites for ordinary guest reads. |
| 06–14 | 8 | Walk through agent setup choices without submitting; show existing scope, effective permissions, connectors and a cited runbook. | “Knowledge cannot grant a permission.” Disclose actual inherited roles, not just desired Reader scope. |
| 14–26 | 12 | [Guest read path](guest-setup.md): fixed target, sequential facts/service/events; inspect provider results and source time. | “Networking reaches the door; identity and JEA determine what is callable.” No raw private event projection. |
| 26–42 | 16 | Human-owned rule → actual recorded incident/initial Teams → proposed approved action → positive recovery/final message evidence. | “These are separate proofs.” If repair/final automation is missing, say so and label the tabletop portion SIMULATED. No fault in this guide. |
| 42–56 | 14 | Show completed schedule history, then [native health/capacity reports](native-reports.md), source coverage and missing data. | “Current CSV free is not raw pool reserve. A gap is not zero. Scheduled output is not same-report refresh.” Do not re-enable a completed task. |
| 56–60 | 4 | Recap only observed outcomes, then point to modular assets and public sources. | “Cite the runbook. Check now. Verify recovery.” Owner-approved public source availability is not live-use acceptance. |
| **Total** | **60** | **6 + 50 + 4** | |

### Safe read prompt — replace placeholders first

```text
For the allowlisted target <SERVER_ID>, use only <APPROVED_GUEST_CONNECTOR>
read tools sequentially: facts; Spooler query; System events with maxCount 3
and lookbackMinutes 60. Show target, source UTC, identity/correlation, provider
coverage and explicit unknowns. Show event count/newest timestamp only.
Do not change anything, send messages or use another target.
```

### Guidance prompt — no live action

```text
Cite the actual reviewed runbook for <SERVER_ID> / Spooler.
Separate current evidence, proposed action, required approval, independent
operator fallback and positive recovery verification. If the source is not
available, say so. Use knowledge retrieval only; do not call operational tools,
repair anything or post messages.
```

## If the demo stalls

One prepared attempt, at most 60 seconds waiting, then the declared recorded
fallback. Say “This is dated evidence, not a successful live check.” If ten
minutes behind, compress demos to **6 + 10 + 12 + 12 = 40 minutes** and keep
the four-minute close. Do not recover time by skipping approval, granting
access, repeating a fault or fabricating native UI evidence.

The operator owns provisioning, permissions and independent recovery. The
agent owns only actions actually exposed and authorized. Successful transport
does not override a denied provider; missing events do not prove health.
Any separately authorized fault needs its own owner, one-use marker, initial
healthy state and enforced recovery deadline; nothing here authorizes one.
