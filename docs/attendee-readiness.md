# Attendee readiness and coverage

**Reviewed October 11, 2026. Owner-approved public attendee starter; no whole-lab acceptance claim.**
This audit starts with a reader who has no presenter subscription, domain,
connector, credentials or report IDs. The owner approved public availability
of this repository on that date; the [publication record](publication-review.md#public-availability-approval---2026-10-11)
distinguishes approval from the visibility change. This grants no access to
the private presenter source, lab or companion runbooks.

Status below describes **what this repository delivers**, not Microsoft product
support: **Supported** = reproducible offline component; **Manual** = supplied
operator procedure with environment prerequisites; **Blocked** = do not claim
the end-to-end scenario until named evidence exists; **Not included** = no
portable implementation here. A lab success is evidence for that lab only.

## Choose the smallest feasible path

| Path | What you need | Honest stopping point |
| --- | --- | --- |
| Offline, no Azure | Repository access and PowerShell 7.5+ | Run synthetic replay and tests below. No sign-in, external data, packages, infrastructure or Azure/model cost. |
| Local component development | Windows, PowerShell 7.5+ and Windows PowerShell 5.1; .NET 10 SDK/cache for MCP | Parse/test JEA; locked restore/test/publish MCP. Tests fake transport and mutations, not a working broker. |
| One real non-Arc Windows guest | Existing AD DS/DNS/DC, one domain-joined broker and one member-server guest; directory, host and PKI owners | Follow [gMSA/guest setup](guest-setup.md) and [compiled service installation](mcp-service-install.md). No LocalBox/cluster/Arc/AMA needed. Real gMSA/JEA/client acceptance remains manual. |
| Native SRE investigation | Previous path plus your approved SRE agent, Entra application caller/role and private remote-MCP route | Prove supported renewable app-only authentication, route, exact tools and live correlation before calling it connected. No presenter bindings are needed or supplied. |
| Windows performance/alerts | Existing Azure VM or Arc server IDs, working AMA Heartbeat/Perf, workspace and scoped permissions | Add only the selected monitoring component after collection preflight. Non-Arc JEA reads do not supply AMA data. |
| Azure Local-specific learning | Your supported system or separately funded [LocalBox lab](localbox.md) | Needed for cluster/storage/VM-specific providers, not for the ordinary guest path. Nested lab behavior is not physical/OEM support proof. |

Run from the repository root:

```powershell
pwsh -NoProfile -File scripts\Invoke-Replay.ps1 -Scenario all
pwsh -NoProfile -File tests\Test-Replay.ps1
pwsh -NoProfile -File scripts\Test-Package.ps1
```

Replay output is computed from synthetic fixtures and compared with expected
answers. It is **not** an alert, native agent conversation, diagnosis of your
machine, MCP response or recovery. Reset by rerunning; no cloud cleanup is needed.

## Scenario coverage and next gates

| Scenario/component | Status | Delivered and next action |
| --- | --- | --- |
| Private, non-Arc guest investigation | **Manual / Blocked end to end** | Fixed JEA reads, C# broker and tests; gMSA creation/KDS/GPO, publish/ACL/SCM/certificate instructions now included. Supply your real guest/provider permissions, actual gMSA tests and approved client. Native SRE auth provisioning recipe still requires owner/product-specific validation. |
| Alert -> investigation | **Manual** | [Five-rule baseline](../infra/hybrid-monitoring/README.md), [service transition](../infra/hybrid-service-monitoring/README.md) and [Arc transition](../infra/hybrid-arc-connectivity/README.md) are separate components. Working collection, native intake/response plan and fresh investigation correlation are separate proofs. |
| Investigation -> approved repair -> verified recovery/notification | **Blocked** | [Spooler-only recovery](../tools/hybrid-service-recovery/README.md) is offline-tested JEA source, not an MCP write tool or native approval bridge. [HIMDS scenario](himds-recovery-demo.md) is a gated design, not a portable executor. No automatic repair, one-use native approval contract, independent recovery or final Teams delivery is delivered end to end. |
| Arc without guest VPN/inbound remoting | **Manual reference / Not included payload** | Existing Connected Machine agent can receive separately authorized Run Command through Azure, without direct RDP/SSH. This is privileged execution, not this JEA boundary. Follow the comparison below; no payload/fault supplied. |
| Scheduled performance checks | **Manual** | Existing scoped telemetry/reader required. Use the [one-run schedule procedure](native-reports.md#scheduled-checks-are-separate-from-reports), verify execution history, then disable/expire the exact owned task. No schedule is enabled by this kit. |
| Native health/capacity reports | **Manual / Blocked deterministic export** | [Recreation prompts and acceptance](native-reports.md) include source contracts and save/reopen/Reload checks. No portable report JSON, lab report IDs or elevated collector. Missing schema/counters or report-eligible tools block that view. |
| Azure Local custom skill | **Manual** | [Neutral skill and additive import](custom-skill.md), no attached tools or new privileges. Verify exact saved content and actual activation separately; a skill cannot grant provider access or authorize precheck reruns. |
| Copilot/Claude -> SRE MCP bonus | **Manual, untested client integration** | [Pinned client instructions](sre-agent-mcp-client-bonus-demo.md). Existing access and a reviewed completed thread required. This is the reverse direction from SRE -> private Windows MCP; no new investigation or repair. |
| New SRE agent and whole lab | **Supported offline / Manual Azure / Not included whole-lab installer** | [Starter IaC](../infra/sre-agent-starter/README.md) compiles/tests but does not configure private connectivity, native connectors, AD, AMA or every required grant. LocalBox is upstream and optional. |

## Arc and private MCP solve different problems

| Boundary | Private MCP/JEA | Arc Run Command |
| --- | --- | --- |
| Network | Client reaches private broker HTTPS; broker reaches guest WinRM/Kerberos | Guest's Connected Machine agent reaches Azure over its approved outbound path; no direct operator RDP/SSH required |
| Identity | Entra application caller -> nonadmin AD service -> guest nonadmin JEA virtual account | Azure operation permission -> agent-executed script; inspect actual configured execution identity |
| Capability | Three fixed read tools; opaque target allowlist | General script execution; `runCommands/write` is not a script-content read-only allowlist |
| Availability | Can inspect a non-Arc guest; depends on AD/broker/private route | Requires a supported connected agent and allowed local policy; Arc Connected alone is not execution proof |
| Failure independence | May remain available when guest Arc/HIMDS is down | Do not rely on the broken Arc path to repair its own unavailable agent |
| Kit content | Portable source, manual host/identity guide, offline tests | Comparison and [official preview guidance](https://learn.microsoft.com/azure/azure-arc/servers/run-command); no command payload or automated SRE action |

"No VPN required" describes the Arc control-plane execution option, **not**
the private MCP path and not a promise of no network, policy, identity or cost
prerequisites. Validate current agent/version/OS/region/feature availability
and permission scope before adopting preview execution. Do not bypass a JEA
provider denial by invoking Arc under a more privileged identity.

## Fixed by this attendee pass

The missing installation middle is now documented: directory/KDS timing,
narrow broker-only password retrieval, gMSA install/test and service-logon/GPO;
complete framework-dependent publish and runtime prerequisites; protected
artifact/config directory; exact certificate-key Read access; Event Log source;
quoted SCM registration; first start/account/PID and layered acceptance;
collision/drift handling and scoped uninstall. A gMSA is no longer presented
as an identity you can simply log into to run the guest test.

The entry point now starts with attendee choices rather than a facilitator
timeline. Corrected stale architecture wording, explicit TCP 5985 encrypted
Kerberos transport, and separate network/authentication gates prevent false
claims that a build, a green connector or a report render completes the lab.
Exported executable source remains unchanged.

## Remaining owner acceptance checklist

1. **Identity/host:** newly provisioned broker/guest, actual gMSA token and
   provider access, live endpoint negative probes, certificate renewal and
   ownership cleanup. Offline tests and an installer's account cannot prove these.
2. **Native SRE:** reviewed renewable application-token setup plus private remote
   MCP routing; product-specific connector configuration and new-attendee
   readback evidence. See the [official-source reconciliation](mcp-service-install.md#native-sre-connector-is-a-separate-availability-gate).
3. **Monitoring/incidents:** complete collection coverage, positive firing and
   recovery observations, native matching/overlap/Review behavior, separately
   approved notification audience. Event absence/expiry is never recovery.
4. **Repair:** remain disabled until the exact action, target, impact, trusted
   human approval, timeout, independent recovery and positive postcheck are
   implemented and accepted. Do not turn a proposal into execution.
5. **Reports/skills/bonus:** actual tool eligibility, versioned save/readback,
   activation or authenticated client evidence in your own environment. Never
   ingest this answer/exercise repository as agent knowledge; import only the
   specifically reviewed neutral skill file if selected.

## Costs, support and cleanup

Budget for your Windows/domain infrastructure and licenses, Azure compute/
storage/networking, SRE/AI usage, telemetry ingestion/retention, dimensional
alert rules, certificate lifecycle and retained artifacts. See [setup costs and
permissions](setup.md#cost-review-before-any-live-provisioning). No numeric
estimate or free whole-lab promise is made without an approved configuration.
Assign a cost/cleanup owner and end time before provisioning or scheduling.

This is owner-maintained demonstration source, not a Microsoft-supported
appliance; upstream preview terms and each OS/service's support requirements
still apply. The [cleanup guide](safety-and-reset.md) links each component's
ownership rules. Never delete a whole resource group/domain, clear logs or
remove shared grants as "reset." Record what was removed, retained or blocked.

## Reproduce the audit checks

The [packaging guide](publication-review.md#reproduce-local-validation) has the
component suites. For these attendee instructions specifically:

```powershell
pwsh -NoProfile -File scripts\Test-AttendeeDocs.ps1
powershell.exe -NoProfile -File scripts\Test-AttendeeDocs.ps1
```

Those checks parse documentation without executing its operational commands,
check source-interface alignment and the no-tools skill contract. Published
artifact validation and the existing MCP/JEA suites are separate. None logs
into Azure, starts the broker, registers JEA or exercises a real domain.
