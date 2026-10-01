# Packaging scope and reproduction

**Private, not publicly released.** This document is a release boundary, not a
claim of Azure acceptance. Begin at the [component quickstarts](../README.md).

## Included

- Owner-authorized SRE starter, five-rule monitoring baseline and ordinary
  Windows JEA capability, preserving component-relative directory layouts.
- Exact allowlisted files in [export-paths.json](../packaging/export-paths.json).
- SHA-256, origin repository and source HEAD context in
  [source-manifest.json](../packaging/source-manifest.json). Every entry is
  explicitly a **source workspace snapshot**, not a claim that pending source
  changes are contained in the recorded commit.
- Packaging-only README changes recorded separately from source hashes.
- Git attributes disable line-ending conversion so clone bytes match the
  recorded hashes even when the operator has global `core.autocrlf` enabled.
- Sanitized MCP configuration examples, integration prerequisites, and the
  [explicit blocked source-export gate](../tools/private-mcp/README.md).
- Original synthetic examples retained as optional offline illustrations.

## Excluded

Unreviewed collection/DCR module, private MCP source with unallowlisted network
constants, lab-bound root operator scripts, private bindings, identities and
hostnames, receipts, binaries, build output, raw diagnostic evidence, internal
planning, presentations, assets, fault scripts and third-party templates.
No source code changes were made to disguise a private dependency.

Native agent YAML/configuration, OAuth completion, private MCP deployment and
whole-lab end-to-end acceptance are **not delivered**. No deployment, endpoint
registration or live resource mutation was performed by packaging.

## Local validation

Run [validate_package.py](../scripts/validate_package.py) from the repository root:

```powershell
python -B scripts\validate_package.py
```

It verifies exported hashes, relative Markdown file links and a documented,
scoped GUID/address/known-binding profile. It is **not a general secret scanner**
or proof that arbitrary content is safe to publish.

Component tests compile Bicep and execute mock-only PowerShell contracts;
Python tests cover the preserved replay and monitoring semantics. Windows
PowerShell 5.1 ownership tests require a short checkout path due to its legacy
file-copy path limit. Local tests do not prove real KQL acceptance, Azure
deployment, effective guest permissions or native SRE correlation.

Packaging validation on 2026-10-01 used Bicep 0.43.8, PowerShell 7.6.6,
Windows PowerShell 5.1.26100.9444 and Python 3.13.15. Passed: 10 original replay
tests, 9 monitoring tests, monitoring PowerShell contracts and Bicep compile,
SRE contract/parameter compilation and regression tests (34 subnet cases and
12 real installed CLI argument sets with mocked transport), all 22 PowerShell
asset parses, and 21 JEA ownership cases in each PowerShell runtime.
MCP .NET build/tests were **not run or claimed** because that source is withheld.

The delivered suites were also rerun successfully from a fresh local Git clone,
without source-workspace files or private configuration. That checkout remained
clean after testing and was removed. A short drive mapping was used for the
Windows PowerShell 5.1 path constraint and removed afterward. The final package
has 66 tracked files and 44 source-manifest entries; its hash check covers actual
clone bytes, not just the pre-commit working tree.

Source READMEs identify local-only validation. Later live results are not
silently imported or represented as proof of this exported snapshot.

Before public release, require owner approval of the exact commit and visibility,
human content/history review, rights review, clean-machine reproduction and
separate live acceptance. This push does not authorize public visibility.
Do not ingest exercise answers or fault material into agent knowledge.
