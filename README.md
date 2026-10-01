# Build a hybrid operations demo

Build a new Azure SRE Agent foundation, add five Windows monitoring rules, or
install a bounded, read-only Windows server diagnostic endpoint. Pick only the
components you need; **ordinary domain-joined Windows servers do not require
Azure Local, LocalBox or Arc for JEA diagnostics**.

**Private attendee starter — not publicly released.** Repository access requires
owner permission. No Azure deployment or live endpoint registration was performed
while packaging this repository. This is not a tested whole-lab installer.

## Choose your starting point

| What you want to build | Runnable component / instructions | Required environment |
| --- | --- | --- |
| A new SRE Agent with identity and telemetry resources | [SRE starter](infra/sre-agent-starter/README.md) | Existing approved Azure RG; Azure CLI, Bicep, PowerShell 7.2+ |
| Five Windows alert rules: heartbeat, CPU, physical memory, disk and counter coverage | [Monitoring baseline](infra/hybrid-monitoring/README.md) | Existing workspace and working AMA Heartbeat/Perf collection, explicit Arc server/Azure VM IDs |
| Bounded facts, Spooler state and recent System/Application events | [Windows JEA capability](tools/hybrid-server/README.md) | Domain-joined member server, Windows PowerShell 5.1, Kerberos/WSMan and dedicated nonadmin caller |
| Connect those reads to an SRE Agent over private MCP | [MCP packaging boundary](tools/private-mcp/README.md) | **Source export blocked pending network-constant review; not runnable from this checkout** |
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
```

Edit the private copies with your own approved bindings. Then follow
[preflight, preview, apply, validate and cleanup](infra/hybrid-monitoring/README.md#prepare-preview-apply-verify).
Collection is a prerequisite, **not installed here**; no DCR module is included.
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

### MCP: exact scope, not an appliance

The approved capability names are `get_server_facts`,
`get_server_service_state` and `get_server_events`. The supplied
[server allowlist example](tools/private-mcp/servers.example.json) is only a
configuration fragment. The reviewed source boundary still embeds lab-specific
network constraints. Exporting those unchanged conflicts with the private-binding
exclusion; changing the code would invalidate the approved immutable snapshot.
Consequently **MCP implementation/build/tests are withheld**, not silently
generalized. See [requirements and remaining release gate](tools/private-mcp/README.md).

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
