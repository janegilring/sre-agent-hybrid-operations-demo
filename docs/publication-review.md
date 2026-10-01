# Packaging scope and reproduction

**Private, not publicly released.** Begin with the [component quickstarts](../README.md).
This refresh exports approved committed source
`04fd291baa88a3370ed17f591e22c15214df865c`, including monitoring correction
`8e823e7`. No source workspace changes, private history or live receipts are
imported. Earlier kit snapshots are superseded by this manifest.

## Included and immutable provenance

- SRE starter, corrected five-rule monitoring, ordinary-server JEA, portable
  MCP C# source/tests/locked dependencies, additive disk collection and
  independently approved Spooler-only recovery.
- Exact reviewed paths in [export-paths.json](../packaging/export-paths.json).
- Original blob IDs, source commit and source/export SHA-256 hashes in
  [source-manifest.json](../packaging/source-manifest.json).
  Source is read directly from committed Git blobs, not a dirty worktree.
- Only README packaging changes differ from original source bytes: generic
  attendee wording, short-path guidance and removal of private receipt paths.
  Those changes are identified separately in the manifest.
- Git attributes preserve exported source line endings on clean clones.
- Existing synthetic exercises remain optional offline illustrations.

## Excluded and remaining gates

Native configuration under `tools/nic-sre-config` remains excluded pending review.
Also excluded: lab-bound private-MCP root operator scripts and their dependent
PowerShell/Python tests, migration receipts, deployment bindings, binaries,
build output, raw operational evidence, internal plans, presentations, fault
scripts, private history and third-party templates.

The portable MCP source no longer supplies private listener or source-network
defaults. Operators must explicitly configure both; there is no allow-any
fallback. Its private configuration migration receipt is deliberately absent.

Disk-collection cleanup requires original configuration fingerprints and exact
resource sets. Existing legacy-deployment cleanup remains held pending separate
private original-snapshot reconciliation. The included receipt helper is **not**
permission to adopt current resources or reconstruct ownership from current GETs.

Five corrected alert rules were separately live-verified in the source lab.
No private RG, subscription or proof receipt is needed to use this package.
That observation does not prove a fresh attendee deployment, complete collection,
native incident routing, guest recovery or notification completion.
The ordinary guest candidate lacks usable domain/Kerberos/WinRM readiness;
end-to-end guest investigation and service recovery remain unproven.

Spooler recovery is offline-tested source, not a connected MCP write tool or
proof of native human approval. Do not grant SRE write access until that
approval boundary is independently verified. No Azure deployment, guest
installation, endpoint registration, fault or service change is performed by
packaging.

## Reproduce local validation

From the repository root:

```powershell
python -B scripts\validate_package.py
python -B -m unittest discover -s tests -v
python -B -m unittest discover -s infra\hybrid-monitoring\tests -v
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Scripts.ps1
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Template.ps1
pwsh -NoProfile -File infra\hybrid-monitoring-collection\tests\Test-Collection.ps1
bicep build infra\hybrid-monitoring-collection\main.bicep --stdout | Out-Null
pwsh -NoProfile -File infra\sre-agent-starter\Test-Contracts.ps1
pwsh -NoProfile -File infra\sre-agent-starter\Test-Regression.ps1
dotnet restore tools\private-mcp\tests\PrivateMcp.Tests.csproj --locked-mode
dotnet test tools\private-mcp\tests\PrivateMcp.Tests.csproj --no-restore
dotnet build tools\private-mcp\src\PrivateMcp.csproj --configuration Release --no-restore
pwsh -NoProfile -File tools\hybrid-server\Test-Offline.ps1
powershell.exe -NoProfile -File tools\hybrid-server\Test-Offline.ps1
pwsh -NoProfile -File tools\hybrid-service-recovery\Test-Offline.ps1
powershell.exe -NoProfile -File tools\hybrid-service-recovery\Test-Offline.ps1
pwsh -NoProfile -File tools\hybrid-service-recovery\Test-InstallerOffline.ps1
powershell.exe -NoProfile -File tools\hybrid-service-recovery\Test-InstallerOffline.ps1
```

Windows PowerShell 5.1 tests need a short checkout path such as
`C:\src\hybrid-demo`. The tests stub transport, service and endpoint mutations;
compiled native interop is not executed against a service. A .NET dependency
restore may download pinned NuGet packages, but does not register a host.

The packaging validator checks source hashes, relative Markdown file links,
known-host fingerprints and scoped GUID/address allowlists. GUIDs are synthetic
test identities, module/capability identities or published built-in roles.
Address exceptions are restricted to documented RFC 5737 examples and explicit
network-policy negative tests; certificate OIDs are not network addresses.
This is **not a general secret scanner** or a substitute for human release review.

## Refresh verification — 2026-10-02

The listed suites passed in a fresh local Git clone without private configuration
or source-workspace files. The clone's tracked/unignored state remained clean.
The validation copy and short drive mapping used for PowerShell 5.1 were removed.

- 99 tracked package files; 79 committed-source entries verified against original
  Git blobs and SHA-256. Executable files remain byte-identical to source.
- 199 MCP tests passed; locked restore and Release build succeeded with zero
  build warnings/errors using .NET SDK 10.0.401.
- 10 replay and 9 monitoring Python tests passed. Corrected five-rule template,
  mock GET recovery checks, collection exact-set/fingerprint/drift/404 cleanup
  tests, and SRE starter contracts/regressions passed.
- Bicep compilation passed (CLI 0.43.8); all 35 shipped PowerShell assets parsed.
  Ordinary-server ownership tests and Spooler runtime/installer tests passed in
  PowerShell 7.6.6 and Windows PowerShell 5.1.26100.9444. Recovery includes 43
  runtime/helper checks per runtime plus the stubbed installer lifecycle.
- Relative Markdown file links and the scoped binding profile passed.

These results are offline source validation, not real guest installation,
service authorization, native approval, recovery or attendee readiness.

Public visibility still requires explicit owner approval of the exact commit,
content/history/rights review and independent deployment acceptance.
Never ingest exercise answers, fault instructions or private receipts into
agent knowledge. A private push is not a claim that the kit is ready end to end.
