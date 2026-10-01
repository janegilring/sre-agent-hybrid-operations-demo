# Hybrid operations demonstration kit

**PRIVATE - prepublication release candidate 0.1.0, 2026-10-01.**
Both this repository and the companion runbooks remain private until explicit
owner approval. **Do not connect this repository to the investigating SRE Agent.**
It contains presenter prompts, expected outcomes and synthetic exercise inputs.

This first release is a reproducible **offline evidence-interpretation exercise**
and a preparation guide for separately approved live demonstrations. It is
**not a reproducible Azure deployment**: no infrastructure installer, private MCP
server, guest executor, credentials or live environment bindings are included.
It makes no claim of successful live inventory, incident routing or remediation.

## Run the offline exercise

Prerequisite: Python 3.11 or later; standard library only. From the repository
root, in PowerShell:

```powershell
python -B scripts\replay.py --scenario all
python -B -m unittest discover -s tests -v
```

The program reads checked-in synthetic fixtures, emits deterministic JSON to
stdout and makes no network calls, cloud changes, notifications or file writes.
It uses fixture-relative timestamps, not the machine clock. The output is
explicitly **SYNTHETIC**, not cached live evidence.

## Start here

| Material | Purpose |
| --- | --- |
| [Setup, costs and permissions](docs/setup.md) | Offline prerequisites and separate live readiness gates |
| [Reference architecture](docs/reference-architecture.md) | Separate telemetry, private node and Arc guest paths |
| [Presenter walkthrough](docs/walkthrough.md) | Prompts, expected outcomes, stop gates and fallbacks |
| [Safe reset](docs/safety-and-reset.md) | No-op offline reset; approval/ownership-first live cleanup |
| [Publication review](docs/publication-review.md) | Exact content boundary and remaining acceptance |
| [Source register](docs/sources.md) | Dated public references and unresolved attribution |
| [Binding worksheet](examples/bindings.example.json) | Non-executable placeholders; never fill with real values here |

Neutral operating procedures live separately in
[sre-agent-hybrid-operations-runbooks](https://github.com/janegilring/sre-agent-hybrid-operations-runbooks).
Only that repository is a candidate for reviewed read-only SRE knowledge
retrieval. Private visibility alone does not prevent a broadly authorized GitHub
connector from reading presenter material.

Original sample code and prose are [MIT licensed](LICENSE). Linked third-party
resources retain their own terms; see [attribution](THIRD-PARTY.md).
No presentation, Microsoft workbook, internal support document, screenshot,
private implementation or private history has been imported.
