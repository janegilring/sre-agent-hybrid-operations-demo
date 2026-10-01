# Build a hybrid operations demo

Build a new Azure SRE Agent foundation, add five Windows monitoring rules, or
install a bounded, read-only Windows server diagnostic endpoint. Pick only the
components you need; **ordinary domain-joined Windows servers do not require
Azure Local, LocalBox or Arc for JEA diagnostics**.

**Private attendee starter — not publicly released.** Repository access requires
owner permission. No Azure deployment or live endpoint registration was performed
while packaging this repository. This is not a tested whole-lab installer.
This revision exports approved source commit `04fd291`. Five corrected alert
rules were separately live-verified in the source environment; that is not
proof of deployment in your environment or end-to-end guest investigation.

## Choose your starting point

| What you want to build | Runnable component / instructions | Required environment |
| --- | --- | --- |
| A new SRE Agent with identity and telemetry resources | [SRE starter](infra/sre-agent-starter/README.md) | Existing approved Azure RG; Azure CLI, Bicep, PowerShell 7.2+ |
| Five Windows alert rules: heartbeat, CPU, physical memory, disk and counter coverage | [Monitoring baseline](infra/hybrid-monitoring/README.md) | Existing workspace and working AMA Heartbeat/Perf collection, explicit Arc server/Azure VM IDs |
| Bounded facts, Spooler state and recent System/Application events | [Windows JEA capability](tools/hybrid-server/README.md) | Domain-joined member server, Windows PowerShell 5.1, Kerberos/WSMan and dedicated nonadmin caller |
| Connect those reads to an SRE Agent over private MCP | [Portable MCP source](tools/private-mcp/README.md) | .NET 10 SDK; Windows host, explicit private configuration, TLS/Entra identity, network and JEA setup |
| Add missing Windows logical-disk counters | [Additive disk collection](infra/hybrid-monitoring-collection/README.md) | Exactly two existing Arc Windows servers in one RG and an existing workspace; ownership fingerprint receipt |
| Separately authorize a fixed Spooler start | [Spooler-only JEA recovery](tools/hybrid-service-recovery/README.md) | Approved noncritical member server and dedicated caller; **not connected to SRE** |
| Build an entire nested Azure Local learning environment | [Pinned official LocalBox and integration sequence](docs/localbox.md) | Upstream Azure, capacity, licensing, network and cost prerequisites |

### Quickstart: new SRE Agent

From the repository root:

```powershell
pwsh -NoProfile -File infra\sre-agent-starter\Test-Contracts.ps1
pwsh -NoProfile -File infra\sre-agent-starter\Test-Regression.ps1
bicep build infra\sre-agent-starter\main.bicep --stdout | Out-Null
```

Follow the [parameter, validate/what-if, deploy and ownership-checked cleanup
commands](infra/sre-agent-starter/README.md#iac-interface-powershell-72-installed-bicep-and-azure-cli).
Use a **new** agent, never adopt a shared one. Target Reader grants are opt-in;
Reader does not complete connector permissions. Native YAML/configuration is
**not yet delivered**. OAuth, supported native exports, network configuration
and end-to-end acceptance remain explicit manual steps in that guide.

### Quickstart: monitoring

```powershell
Copy-Item infra\hybrid-monitoring\config.example.json infra\hybrid-monitoring\config.local.json
Copy-Item infra\hybrid-monitoring\targets.example.json infra\hybrid-monitoring\targets.local.json
python -B -m unittest discover -s infra\hybrid-monitoring\tests -v
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Scripts.ps1
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Template.ps1
```

Edit the private copies with your own approved bindings. Then follow
[preflight, preview, apply, validate and cleanup](infra/hybrid-monitoring/README.md#prepare-preview-apply-verify).
Collection is a prerequisite. The optional
[disk-only DCR component](infra/hybrid-monitoring-collection/README.md) adds one
counter to exactly two Arc servers; it does not bootstrap all AMA collection.
This does not implement Arc connection-state or service-state alerts.

### Quickstart: ordinary Windows server

Validate the portable source locally:

```powershell
pwsh -NoProfile -File tools\hybrid-server\Test-Offline.ps1
powershell.exe -NoProfile -File tools\hybrid-server\Test-Offline.ps1
pwsh -NoProfile -File tools\hybrid-server\Test-OwnershipOffline.ps1
```

On an approved member server, copy `tools\hybrid-server`, then use elevated
Windows PowerShell 5.1:

```powershell
.\Install-HybridServerReadOnly.ps1 -CallerIdentity 'EXAMPLE\mcpRead$' -WhatIf
# After approval, repeat without -WhatIf.
# As the actual dedicated caller, validate effective permissions:
.\Test-HybridServerReadOnly.ps1 -ComputerName server01.example.test `
    -ExpectedMachine SERVER01 -ExpectedCaller 'EXAMPLE\mcpRead$'
# After sessions end and separately owned provider grants are rolled back:
.\Remove-HybridServerReadOnly.ps1 -WhatIf
```

Read the [full setup/cleanup contract](tools/hybrid-server/README.md) before
installation. No arbitrary shell, service remediation, directory account,
provider ACL grant or live WinRM restart is supplied.

### Quickstart: portable MCP source, not an appliance

```powershell
dotnet restore tools\private-mcp\tests\PrivateMcp.Tests.csproj --locked-mode
dotnet test tools\private-mcp\tests\PrivateMcp.Tests.csproj --no-restore
dotnet build tools\private-mcp\src\PrivateMcp.csproj --configuration Release --no-restore
```

The capability names are `get_server_facts`,
`get_server_service_state` and `get_server_events`. The supplied
[server allowlist example](tools/private-mcp/servers.example.json) is only a
configuration fragment. `ListenAddress` and `AllowedSourceCidrs` are now required
operator configuration, with no lab-address fallback. The unchanged sample
intentionally fails identity validation. Follow the [build, TLS, service identity,
private network and migration instructions](tools/private-mcp/README.md); service
registration and guest setup are separate, not an instant appliance installer.
Keep LocalBox node capabilities disabled for ordinary servers.

### Optional: disk collection and fixed service recovery

```powershell
bicep build infra\hybrid-monitoring-collection\main.bicep --stdout | Out-Null
pwsh -NoProfile -File infra\hybrid-monitoring-collection\tests\Test-Collection.ps1
pwsh -NoProfile -File tools\hybrid-service-recovery\Test-Offline.ps1
pwsh -NoProfile -File tools\hybrid-service-recovery\Test-InstallerOffline.ps1
```

Read the collection guide's exact three-resource what-if and
`New-CollectionReceipt` instructions before separately approved deployment.
Legacy receipts without proven original snapshots/fingerprints do **not**
authorize cleanup; reconciliation is a separate gate.

Spooler recovery exposes only a fixed state read and `Start-HybridSpooler`.
It has no fault injection, arbitrary service control, MCP write tool or native
approval integration. Follow its [installation and ownership cleanup guide](tools/hybrid-service-recovery/README.md);
do not grant an SRE identity write access until native human-approval behavior
is independently proved.

### What is not ready

Native configuration (`tools\nic-sre-config`) is deliberately excluded pending
review. The ordinary-server candidate lacks usable domain/Kerberos/WinRM
readiness, so no end-to-end guest read or recovery is claimed. Source alert
verification does not prove native incident routing, approval, final Teams
notification, guest recovery or a complete attendee lab.

## Guides and optional illustrations

- [Setup, permissions and costs](docs/setup.md)
- [LocalBox upstream and sequencing](docs/localbox.md)
- [Reference architecture](docs/reference-architecture.md)
- [Safety and cleanup](docs/safety-and-reset.md)
- [Optional offline exercise and presenter walkthrough](docs/walkthrough.md)
- [Source references](docs/sources.md), [attribution](THIRD-PARTY.md)
- [Packaging scope and validation](docs/publication-review.md)

The preserved synthetic examples are optional teaching illustrations, not live
evidence or the purpose of this starter:

```powershell
python -B scripts\replay.py --scenario all
python -B -m unittest discover -s tests -v
```

**Do not ingest this repository into agent knowledge.** It includes expected
answers and exercise material. Restrict any knowledge connector to separately
reviewed neutral runbooks; never ingest fault scripts, private bindings or raw
operational results. The companion runbooks repository is also private unless
its owner separately approves release.

Original owner-authorized code and prose retain the [MIT license](LICENSE).
Linked third-party content is not vendored or relicensed.
