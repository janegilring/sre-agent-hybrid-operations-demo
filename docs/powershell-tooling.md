# PowerShell-first tooling and maintainer exception

Attendees need **PowerShell 7.5 or later** (`pwsh`) for the synthetic replay,
package validator and translated component tests. These use built-in PowerShell
and .NET APIs, with no modules to install. JSON is deliberately read with
`-DateKind String` so UTC evidence timestamps are validated as supplied rather
than silently converted to local times; this requires 7.5
([`ConvertFrom-Json -DateKind`](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5#-datekind)).
Shared JSON parsing first rejects comments/trailing commas with .NET's strict
JSON parser. See the
[official Windows installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).

Windows PowerShell 5.1 remains supported for the existing JEA/recovery guest
scripts and `Test-AttendeeDocs.ps1`, not the new tooling. PowerShell 7 and Windows
PowerShell install side by side; do not change the JEA endpoint host to run
these tests. Azure CLI/Bicep and the .NET 10 SDK remain component-specific
prerequisites. Azure CLI may bundle its own Python runtime; attendees do not
install, configure or invoke Python separately.

## Replacements

| Previous tool | PowerShell entry point | Preserved contract |
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
this guarantee. The user explicitly retained it for maintainers.

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
[offline validation commands](publication-review.md#reproduce-local-validation);
an attendee-only green run is not the maintainer gate.

## Derivative provenance

The four translated exported tools and the narrowly adapted SRE regression
runner are identified individually in `packaging\source-manifest.json`.
Each retains the original source commit/blob/hash, records the original
`sourcePath`, and declares `powershell-tooling-port-v1` with an updated export
hash. The package validator permits these exact path/source-hash pairs only;
this is not a general permission to modify executable exports.
Deployed C#/JEA/ARM component source and the native skill are unchanged.
Older validation records describe the implementations tested at that time.
