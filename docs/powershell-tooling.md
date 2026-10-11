# PowerShell-first tooling and maintainer exception

Attendees need **PowerShell 7.5 or later** (`pwsh`) for the synthetic replay,
package validator and component tests. These use built-in PowerShell
and .NET APIs, with no modules to install. JSON is deliberately read with
`-DateKind String` so UTC evidence timestamps are validated as supplied rather
than silently converted to local times; this requires 7.5
([`ConvertFrom-Json -DateKind`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5#-datekind)).
Shared JSON parsing first rejects comments/trailing commas with .NET's strict
JSON parser. See the
[official Windows installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).

Windows PowerShell 5.1 remains supported for the existing JEA/recovery guest
scripts and `Test-AttendeeDocs.ps1`, not the PowerShell 7.5 tooling. PowerShell 7 and Windows
PowerShell install side by side; do not change the JEA endpoint host to run
these tests. Azure CLI/Bicep and the .NET 10 SDK remain component-specific
prerequisites. Azure CLI may bundle its own Python runtime; attendees do not
install, configure or invoke Python separately.

## Tool entry points

| Purpose | PowerShell entry point | Contract |
| --- | --- | --- |
| Synthetic replay | `scripts\Invoke-Replay.ps1 -Scenario all` | Exact synthetic scope, timestamps, counts, evidence gaps and output shape |
| Replay tests | `tests\Test-Replay.ps1` | Fixture answers, independent computation, freshness bounds, null/partial data, rejecting mutations and CLI failure |
| Package validator | `scripts\Test-Package.ps1` | Export hashes, exact allowlist/origins, private-binding profile, inactive diagrams and relative links |
| Arc inputs | `infra\hybrid-arc-connectivity\Test-Inputs.ps1` | Literal exact-scope IDs, subscription, duplicates, ownership and ARM UUIDv5 names |
| Arc tests | `infra\hybrid-arc-connectivity\Test-Connectivity.ps1` | Input rejections, compiled template, per-machine equality, transition and no implicit recovery |
| Monitoring tests | `infra\hybrid-monitoring\tests\Test-Queries.ps1` | Inventory-driven absence, closed-bin/sample bounds, percent units, disk instances and query contracts |
| Service-event tests | `infra\hybrid-service-monitoring\tests\Test-Contract.ps1` | Compiled Bicep, exact event/time/source semantics, no inferred current state |

Run them with `pwsh -NoProfile -File <path>`. Tests are offline reference models
and contracts, not KQL execution or live provider acceptance. The package
validator is a scoped binding check, not a general secret scanner.
`tests\Test-Package.ps1` exercises positive and rejecting fixtures in its own
temporary Git repository; it never edits a real package to inject faults.

## Required maintainer SDK gate

**One Python file is intentionally retained:** `infra\sre-agent-starter\test_role_cli.py`.
It tests the installed Azure CLI's actual Python role-list validator and genuine
SDK `ItemPaged` behavior over two mocked pages, including inherited/foreign
scope rejection and the final page. A PowerShell model cannot substitute for
this guarantee.

Before merging or publishing any tooling change, run:

```powershell
pwsh -NoProfile -File infra\sre-agent-starter\Test-Regression.ps1 -IncludeMaintainerSdk
```

For an Azure CLI installation other than the Windows MSI layout:

```powershell
pwsh -NoProfile -File infra\sre-agent-starter\Test-Regression.ps1 `
    -IncludeMaintainerSdk -AzureCliPython '<Azure-CLI-installation>\python.exe'
```

This command fails if the SDK test cannot run; it never silently skips it.
The default attendee run prints **NOT RUN** for SDK acceptance and still runs
the PowerShell subnet, ownership, cleanup and command-argument checks.
There is currently no checked-in CI workflow. Any future CI must run the
maintainer command above, in addition to the
[offline validation commands](#local-validation);
an attendee-only green run is not the maintainer gate.

## Local validation

Run the package, link and documentation checks from the repository root:

```powershell
pwsh -NoProfile -File scripts\Test-Package.ps1
pwsh -NoProfile -File tests\Test-Package.ps1
pwsh -NoProfile -File scripts\Test-AttendeeDocs.ps1
powershell.exe -NoProfile -File scripts\Test-AttendeeDocs.ps1
pwsh -NoProfile -File tests\Test-Replay.ps1
```

The documentation check parses command blocks without executing installation
commands. It checks source interfaces and the neutral skill's boundaries.
The package check verifies relative Markdown file links, the exact export
allowlist and hashes; it does not check external website availability.

For changes to a component, also run its own offline checks:

| Component | Instructions |
| --- | --- |
| SRE starter | [Contracts and regression, including the maintainer SDK gate](../infra/sre-agent-starter/README.md#iac-interface-powershell-72-installed-bicep-and-azure-cli) |
| Monitoring baseline | [Query, script and template tests](../infra/hybrid-monitoring/README.md#tests) |
| Arc connectivity | [Bicep and input/transition checks](../infra/hybrid-arc-connectivity/README.md#prepare-and-test-no-deployment) |
| Disk collection | [Collection tests](../infra/hybrid-monitoring-collection/README.md) |
| Service-event monitoring | [Bicep and event-contract checks](../infra/hybrid-service-monitoring/README.md#ownership-cleanup-and-offline-checks) |
| Windows JEA | [Offline checks](../tools/hybrid-server/README.md#offline-validation-and-teardown); also run `Test-OwnershipOffline.ps1` with both Windows PowerShell 5.1 and PowerShell 7 |
| Spooler recovery | [Runtime and installer checks on both PowerShell hosts](../tools/hybrid-service-recovery/README.md#offline-validation) |
| Private MCP | [Locked restore, tests, build and publish](../tools/private-mcp/README.md#build-and-test) |

After publishing MCP, optionally pass
`-PublishDirectory tools\private-mcp\src\bin\publish\win-x64` to
`scripts\Test-AttendeeDocs.ps1` on either supported host to check the
framework-dependent Windows x64 artifact shape. This does not start the broker.

## Export integrity

[source-manifest.json](../packaging/source-manifest.json) records original
source commits/blobs/hashes, export hashes and documented transformations.
[export-paths.json](../packaging/export-paths.json) is the exact component
allowlist. A documentation adaptation must retain its original source identity
and record its changes and new export hash. The validator permits only the
listed executable tooling derivatives; do not relax it to admit other changes.
