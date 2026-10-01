# Publication and reproduction review

Status: **private prepublication candidate 0.1.0**, 2026-10-01.

## Included and deliberately excluded

Included: original reference prose, placeholder worksheet, synthetic evidence
fixtures, deterministic offline Python replay and tests, source attribution and
MIT license. No code is copied from a private implementation.

Excluded: private history/plans, actual subscriptions/tenants/principals, private
hostnames/addresses, actual environment paths, raw logs/transcripts, credentials,
support PDFs, third-party workbook or screenshots, presentation assets,
deployment automation, fault/repair scripts and connector secrets.

The companion runbooks repository is the neutral knowledge candidate. This
repository contains exercise answers and must remain inaccessible to the
investigating agent, including through broadly authorized GitHub tools.

## Exact initial file allowlist

```text
.gitignore
LICENSE
README.md
SECURITY.md
THIRD-PARTY.md
docs/publication-review.md
docs/reference-architecture.md
docs/safety-and-reset.md
docs/setup.md
docs/sources.md
docs/walkthrough.md
examples/bindings.example.json
examples/scenarios.json
scripts/replay.py
tests/test_replay.py
```

## Gates before a public release

- Owner approval of visibility, exact commit/file set, original authorship/MIT
  choice and third-party attribution. Do not change visibility automatically.
- Human sensitive-data review in addition to lexical/identifier checks, including
  full Git history and metadata. Only fresh authored history is intended here.
- Reproduction on a clean environment. Current offline commands are the only
  reproducible implementation offered; a fresh-machine independent rehearsal
  and any Azure deployment reproduction remain pending.
- Recheck live documentation/product support, upstream workbook revision and
  provider/transport limitations. Do not treat a documentation view as the
  installed product version.
- Resolve the exact requested MCP article attribution or explicitly keep it
  unresolved; see [source register](sources.md). Similar titles are not substitutes.
- Separate approval for future deployment/trigger/reset implementation, with
  tests and measured live evidence. Do not call this kit a complete cloud setup.

Do not close broader publication/reproduction acceptance merely because a private
push succeeds. Public release is not required for a private presentation.
Changes should be freshly authored or narrowly ported after review, never synced
by copying private repository history, branches, automation or secrets.
