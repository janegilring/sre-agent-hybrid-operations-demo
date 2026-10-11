# Packaging scope and reproduction

**Private, not publicly released.** Begin with the [component quickstarts](../README.md).
**Historical packaging baseline, before the current guest refresh:** that
follow-up refreshed exactly five monitoring files from
`1ceb2a76fd9efbf0bf736da10d665488f331afb6` and adds two reviewed diagram assets
from `0a195563ebb866c2f2da39b00cd9b11973a801c4` (unchanged at `1ceb2a7`).
At that time, all other exports and their provenance remained at `c086d8d`/`c814605`,
including monitoring recovery semantics, cleanup WhatIf and per-machine Arc scope.
No later private-doc commit, source workspace changes, private history or live
receipts were imported in that batch. For the subsequent 30-file guest/MCP
provenance refresh, use [current sources](sources.md) and the
[current manifest](../packaging/source-manifest.json), not this historical note.

## Included and immutable provenance

### October 11 PowerShell-first follow-up

Attendee replay, package checks, Arc inputs and component reference-model tests
now use PowerShell 7.5+. The only retained Python entry point is the installed
Azure CLI SDK test, explicitly required for maintainers with
`Test-Regression.ps1 -IncludeMaintainerSdk`, not for attendees.
There is no existing checked-in CI workflow; future CI must retain that gate.
See [tooling and derivative provenance](powershell-tooling.md).

The manifest still has 93 entries. Four former exported Python tools are
explicit PowerShell derivatives, and the SRE regression runner has a narrow
invocation adaptation. Their original commit/blob/source hashes are retained
with original source paths and individually allowlisted transformation metadata.
Four component README export hashes reflect the new commands.
All other exported bytes, including the retained SDK test, C#/JEA/ARM components
and native skill, remain unchanged from the preceding attendee snapshot.

### Earlier October 11 attendee onboarding follow-up

The [readiness audit](attendee-readiness.md), expanded [gMSA/guest guide](guest-setup.md),
[Windows service installation runbook](mcp-service-install.md), schedule guidance,
[skill import guide](custom-skill.md) and `scripts\Test-AttendeeDocs.ps1` are
original portable kit documentation/checks, not exported lab operator scripts.
They perform no live configuration. The two JEA/MCP README export hashes now
record their additional attendee links/publish wording; their original source
blob IDs, source hashes and origin commits remain intact. All exported
executable source is unchanged.

One neutral `skills/azure-local-operations-triage/SKILL.md` file is newly
allowlisted from committed source `908912037636dcfb61ce9593a4f2b9d71ec9df55`.
Its instruction text matches the committed blob, with only CRLF normalization;
the source README, private receipts and native configuration are not copied.
The manifest now has **93** entries. The validator requires that exact skill
path/revision and rejects other unreviewed `skills/` additions, just as it
already rejects unreviewed `tools/` and `infra/` files. No exclusions were
relaxed to admit deployment scripts.

### Earlier component exports

- SRE starter, corrected five-rule monitoring, ordinary-server JEA, portable
  MCP C# source/tests/locked dependencies, additive disk collection and
  independently approved Spooler-only recovery, plus the six-file English
  Spooler stopped-transition monitoring starter and five-file per-machine
  Arc-connectivity component.
- Exact reviewed paths in [export-paths.json](../packaging/export-paths.json).
- Original blob IDs, source commit and source/export SHA-256 hashes in
  [source-manifest.json](../packaging/source-manifest.json).
  Source is read directly from committed Git blobs, not a dirty worktree.
- Before the PowerShell-first follow-up, only documented Markdown packaging changes differed from original source bytes: generic
  attendee wording, short-path guidance, removal of private receipt paths and
  explicit legacy reconciliation HELD status.
  Those changes are identified separately in the manifest.
- Git attributes preserve exported source line endings on clean clones.
- Existing synthetic exercises remain optional offline illustrations.
- Two sanitized, original diagram assets (SVG and editable Excalidraw) provide
  a reusable Azure-hosted LocalBox overview, not a live acceptance report.
  Private presentation notes, planning documents and raw evidence are excluded.

## Excluded and remaining gates

Native configuration under `tools/nic-sre-config` remains unreviewed and excluded.
Also excluded: lab-bound private-MCP root operator scripts and their dependent
PowerShell/Python tests, migration receipts, deployment bindings, binaries,
build output, raw operational evidence, internal plans, presentations, fault
scripts, private history and third-party templates.
The approved standalone architecture assets are the only diagram additions;
no presentation deck, private demo architecture notes or native configuration
is included.

The portable MCP source no longer supplies private listener or source-network
defaults. Operators must explicitly configure both; there is no allow-any
fallback. Its private configuration migration receipt is deliberately absent.

Disk-collection cleanup requires original configuration fingerprints and exact
resource sets. Legacy reconciliation concluded **HELD** after original snapshots
were overwritten. No resource cleanup was performed or is authorized without
fresh owner review. The included receipt helper is **not**
permission to adopt current resources or reconstruct ownership from current GETs.

Five corrected alert rules were separately live-verified in the source lab.
No private RG, subscription or proof receipt is needed to use this package.
That observation does not prove a fresh attendee deployment, complete collection,
native incident routing, guest recovery or notification completion.
These historical packaging observations are not current source-lab status.
End-to-end guest investigation, real gMSA/provider acceptance and service
recovery remain unproven **in an attendee environment**. Configured connector
visibility is not evidence that a main-agent conversation can discover and
invoke its tools; require a fresh operational trace.

Spooler recovery is offline-tested source, not a connected MCP write tool or
proof of native human approval. Do not grant SRE write access until that
approval boundary is independently verified. No Azure deployment, guest
installation, endpoint registration, fault or service change is performed by
packaging.

The new service-event starter is offline source only: no AMA installation,
continuous current-state monitoring, service-stream coverage, live deployment,
native approval or recovery is proven. Its optional English 7036 rule reports
an observed stopped transition. Zero matching events is UNKNOWN, and neither
event expiry nor an alert's user state establishes recovery.

The Arc component creates one rule per exact selected machine, with one machine
scope and a matching flat resource-ID equality. Four targets require four rules
and four activity-log rule slots, never a broad-scope substitute. The owner
reports successful source-environment deployment of the revised four-rule set.
No live verification was repeated during packaging, and no IDs, raw failed
candidate history or private receipts are included. The authoring-time README
acceptance gate remains relevant to each new deployment. Event absence is
UNKNOWN; deployment success is not native routing or notification proof.
The live operating window is closed and this closeout authorizes no live action.

## Reproduce local validation

From the repository root:

```powershell
pwsh -NoProfile -File scripts\Test-Package.ps1
pwsh -NoProfile -File tests\Test-Package.ps1
bicep build infra\hybrid-arc-connectivity\main.bicep --stdout | Out-Null
bicep build-params infra\hybrid-arc-connectivity\main.example.bicepparam --stdout | Out-Null
pwsh -NoProfile -File infra\hybrid-arc-connectivity\Test-Connectivity.ps1
pwsh -NoProfile -File tests\Test-Replay.ps1
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Queries.ps1
pwsh -NoProfile -File infra\hybrid-service-monitoring\tests\Test-Contract.ps1
bicep build-params infra\hybrid-service-monitoring\example.bicepparam --stdout | Out-Null
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Scripts.ps1
pwsh -NoProfile -File infra\hybrid-monitoring\tests\Test-Template.ps1
pwsh -NoProfile -File infra\hybrid-monitoring-collection\tests\Test-Collection.ps1
bicep build infra\hybrid-monitoring-collection\main.bicep --stdout | Out-Null
pwsh -NoProfile -File infra\sre-agent-starter\Test-Contracts.ps1
pwsh -NoProfile -File infra\sre-agent-starter\Test-Regression.ps1 -IncludeMaintainerSdk
dotnet restore tools\private-mcp\tests\PrivateMcp.Tests.csproj --locked-mode
dotnet test tools\private-mcp\tests\PrivateMcp.Tests.csproj --no-restore
dotnet build tools\private-mcp\src\PrivateMcp.csproj --configuration Release --no-restore
dotnet publish tools\private-mcp\src\PrivateMcp.csproj --configuration Release `
    --runtime win-x64 --self-contained false --no-restore `
    --output tools\private-mcp\src\bin\publish\win-x64
pwsh -NoProfile -File scripts\Test-AttendeeDocs.ps1 `
    -PublishDirectory tools\private-mcp\src\bin\publish\win-x64
powershell.exe -NoProfile -File scripts\Test-AttendeeDocs.ps1 `
    -PublishDirectory tools\private-mcp\src\bin\publish\win-x64
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

## PowerShell-first verification - 2026-10-11

The revised package contains **126 files / 93 source-hash entries**. All 93
original commit/blob/source-hash identities were compared with `3841e9f` and
preserved; only five tooling derivatives and four component README exports
changed. The retained SDK test and native skill are byte-identical.

On PowerShell 7.6, the replay, package checker, **38 rejecting package mutations**,
Arc inputs/template suite, nine monitoring and eleven service-event contract
groups, and attendee SRE regression all passed with `python`, `python3` and `py`
absent from the process PATH. Strict JSON, malformed UTF-8, diagram activity,
source/derivative tampering, unreviewed exports, scoped addresses/GUIDs, synthetic
hostname-digest detection and broken links were exercised without editing the
real package. Replay preserves unknown/null counts and rejects invalid scopes,
statuses, budgets and timestamps; Arc naming matches a fixed prior UUIDv5 vector.

The separate mandatory maintainer run also passed: **12 production argument
sets**, real installed Azure CLI validation, genuine SDK two-page iteration and
exact-scope filtering with transport replaced. The existing SRE suite passed
34 subnet cases and mocked ownership cleanup. Existing monitoring/collection
contracts and **210 MCP tests** passed. The 16 onboarding PowerShell blocks,
source/skill contracts and five skill mutations still passed on both Windows
PowerShell 5.1 and PowerShell 7.6. The new tooling requires 7.5+ and is not claimed
to execute on 5.1. No Azure, AD, service or live endpoint operation was performed.

## Earlier attendee onboarding verification - 2026-10-11

The attendee snapshot has **122 tracked files and 93 source-hash entries**.
All 92 previous source-origin records remain unchanged against kit commit
`6b4d046`; only the two component README packaging adaptations and the explicitly
allowlisted skill differ in export scope. No executable component was changed.

Offline checks in the implementation worktree passed:

- Locked MCP restore, **210 tests**, Release build with zero warnings/errors,
  and framework-dependent `win-x64` publish. Published artifact checks verified
  x64 and both required .NET/ASP.NET Core 10 frameworks.
- All **16** new PowerShell documentation blocks parsed in PowerShell 7 and
  Windows PowerShell 5.1. Source contracts, the neutral skill contract and five
  negative skill mutations passed. JEA ownership checks (**21** per runtime),
  recovery checks (**43** per runtime) and stubbed recovery installer/cleanup
  lifecycle passed in both runtimes.
- **10** replay, **9** monitoring, **15** Arc and **11** service-event tests;
  monitoring, collection and SRE starter contract/regression suites; and local
  Bicep example-parameter/template compilation passed. Azure CLI, provider,
  service, endpoint and transport mutations were mocked.
- Package source/export hashes, relative Markdown file links and the scoped
  identifier/address profile passed. Intentional CRLF skill-export bytes were
  preserved; whitespace validation treated carriage returns as line endings.

A fresh local clone of `ec525ae` independently passed the package check, locked
MCP restore, all 210 MCP tests, framework-dependent publish and new documentation/
published-artifact checks in both PowerShell runtimes and remained clean. This
clean-clone check did not repeat every other component suite or perform a live
install. Independent read-only review approved the unchanged guest setup,
service installation, readiness audit and documentation-check artifacts at that
snapshot, including a native-argument mock preserving executable-path quotes
and the literal gMSA account suffix.
None of these results proves AD replication, effective gMSA rights, TLS key
access, SCM startup, guest-provider access, native discovery/authentication,
human-approved repair or attendee deployment. Those acceptance gates remain
explicit in the [readiness audit](attendee-readiness.md).

## Historical follow-up verification — 2026-10-02

This package has **112 tracked files and 92 source-hash entries**:
80 retain `c086d8d`, five retain `c814605`, five monitoring files use `1ceb2a7`,
and two diagram assets use `0a19556`. All 85 unaffected prior entries and export
bytes were verified unchanged against kit commit `de59153`. All 92 source
hashes were verified against their original committed blobs; the seven
refreshed/new files are exact byte copies.

A fresh Git clone passed:

- Monitoring PowerShell regressions, including trimmed inventory/signal joins,
  absence of blank current-query block separators and final tabular expressions.
- Bicep compilation and compiled-template checks that both query boundaries
  are trimmed, alongside the existing five-rule/recovery contracts.
- All nine monitoring Python tests.
- All source/export hashes, relative Markdown links and scoped binding checks.
  SVG XML and Excalidraw JSON checks found no embedded images, external links,
  active SVG elements or zero-size text.

The independent visual approval was inherited from the exact approved diagram
source; no new visual acceptance or live environment status is asserted.
The clone stayed clean and was removed. Unchanged component suites were not
rerun. This refresh made no Azure call or live query patch and did not reproduce
the user's portal browser selection. Full-query API behavior and portal
current-block execution remain distinct, as the updated component README
explains. Private notes, planning, raw receipts and native configuration remain
excluded; repository visibility remains private.

## Previous closeout verification — Arc source c814605, 2026-10-02

That private package contained **110 tracked files and 90 source hashes**.
All previous 85 exports and their provenance entries were verified unchanged
against kit commit `e8ee288`. The five new files exactly match committed source
blobs at `c814605`, and all 90 source origins were hash-verified.

A fresh Git clone passed the 15 Arc input/template/transition tests, Bicep
compilation and example-parameter compilation, all export hashes, relative
Markdown file links and the scoped binding profile. Tests include four-machine
exact sets, similarly named machines/descendants, flat equality, invalid/broad
scope rejection, deterministic names and absence of implicit recovery.
The clone stayed clean and was removed afterward.

Unchanged component suites were not rerun for this five-file closeout.
No Azure calls, deployment, live verification, Teams messages, resource cleanup
or public release occurred. Native configuration remains excluded. Source-lab
deployment success is owner-reported context, not an attendee end-to-end claim.

## Previous increment verification — source c086d8d, 2026-10-02

That package contained **105 tracked files and 85 source-manifest entries**.
Every entry was verified against its committed blob at `c086d8d`; executable
files are byte-identical. Only the six approved service-monitoring files and
the two monitoring cleanup/test files changed in executable source scope.
All other source blobs were checked unchanged before their provenance was
repinned. No content from the later private-doc commit was exported.

A fresh Git clone passed:

- All 11 service-monitoring contract tests, including Bicep compilation; the
  documentation-only parameter file also compiled offline.
- The monitoring PowerShell suite, including all **five owned cleanup WhatIf
  previews**, zero mocked Azure deletes and an unchanged receipt hash.
- The existing nine monitoring Python tests and five-rule template contracts.
- All 85 export hashes, portable relative Markdown file links and scoped
  identifier/address/known-binding checks.

The clone remained clean and was removed. No private configuration, Azure
operation, real receipt modification, guest installation or resource cleanup
was needed. Unchanged MCP/JEA/recovery suites were not rerun for this bounded
increment; their previous clean-clone results are recorded below.

## Previous component verification — source 04fd291, 2026-10-02

Before this increment, the previously included component suites passed in a fresh local Git clone without private configuration
or source-workspace files. The clone's tracked/unignored state remained clean.
The validation copy and short drive mapping used for PowerShell 5.1 were removed.

- That revision had 99 tracked package files and 79 committed-source entries verified against original
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
