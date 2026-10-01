# Additive Windows disk collection

`main.bicep` adds one uniquely owned Windows DCR and exactly two associations
on existing Arc servers in the deployment resource group. It collects
`\LogicalDisk(*)\% Free Space` every 60 seconds into an existing workspace's
`Perf` table. No agents, extensions, role assignments, endpoints, alerts or
existing DCRs are changed.

Use the existing workspace region. Before deploying, inventory **all** DCR
associations on both targets, inspect their referenced rules for overlapping
collection, verify Windows/AMA and capture existing resource hashes.
Compile Bicep, run ARM validation and JSON incremental what-if;
`Assert-CollectionWhatIf` rejects anything except the three exact new IDs.
Abort if any proposed name exists. Recheck names and pre-state immediately
before applying once. Preserve a private receipt containing subscriptionId,
resourceGroup, name, ownerToken, dcrId, machineIds and associationIds.

After deployment, immediately read all three resources and verify ownership.
Before allowing subsequent changes, persist the full original GET responses
and a versioned fingerprint receipt using the actual helper below:

```powershell
. .\Common.ps1
# $receipt contains the seven deployment identity fields listed above.
$original = @(@($receipt.associationIds) + @($receipt.dcrId) |
    ForEach-Object { Get-CollectionResource $receipt.subscriptionId $_ })
$original | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath .\original-deployment-resources.json -NoClobber
New-CollectionReceipt -Receipt $receipt -OriginalDeploymentSnapshots $original |
    ConvertTo-Json -Depth 100 | Set-Content -LiteralPath .\receipt.json -NoClobber
```

Run this only as the immediate post-deployment receipt-creation step, not to
adopt resources later. Keep these files private and immutable. The helper
performs exact scope, uniqueness and ownership checks without network calls.
It records `fingerprintVersion: 1` and three `{ id, sha256 }` entries.

Query fresh
`Perf` grouped by exact `_ResourceId`, `ObjectName`, `CounterName`,
`InstanceName` and timestamps. Verify `C:` independently on each node before
using it in expected alert inventory; discovered data disks need owner inventory
validation. Preserve original DCR/association hashes and fresh CPU, memory and
Heartbeat. ARM installed-memory inventory is not guest usable-memory proof.

Rollback preview: `.\Cleanup.ps1 -ReceiptPath <private-receipt> -WhatIf`.
Actual rollback requires explicit approval; remove the two owned associations
then their DCR, never unrelated collection. Cleanup validates the entire
receipt before any ARM request, then checks all three resources before the
first delete. It fails closed on missing fingerprints, missing resources,
ownership changes or configuration drift, including added counters, data flows,
destinations, workspace targets and association targets. Each deletion requires
a subsequent owned-ID GET returning the CLI's ResourceNotFound/NotFound (404);
other failures or a still-present resource stop further deletion.

Fingerprints recursively sort JSON object keys ordinally; array order remains
significant. They include all returned configuration, IDs/scopes (top-level ID
case is normalized), kind, location, and all tags, including additional tags.
Only top-level `etag`, `systemData` and `properties.provisioningState` are
excluded: these are concurrency, audit and lifecycle metadata rather than
collection configuration. Unknown properties remain included, fail-safe.
Avoid concurrent writers during cleanup; validation is not an ARM transaction.

### Explicit legacy receipt reconciliation — cleanup remains held

Never fill missing fingerprints from current GETs. For a legacy deployment,
the owner must independently verify the provenance of the preserved original
full resource snapshots and their matching deployment identity receipt.
These files are inputs only; do not overwrite them. Confirm that the observations
are the original, successful post-deployment full GET responses, not current
inventory, templates, hashes alone or another deployment's observations.
Extract the three complete resource objects into `$original` (an array, preserving
every field; unwrap any archive envelope) and load the identity receipt as `$legacy`.
Then, offline:

```powershell
$candidate = New-CollectionReceipt -Receipt $legacy -OriginalDeploymentSnapshots $original
# $current is a separately obtained, authorized read-only observation of all
# three resources. It is used only for comparison, never to create $candidate.
$comparison = New-CollectionReceipt -Receipt $legacy -OriginalDeploymentSnapshots $current
if ((Get-CollectionHash $candidate.fingerprints) -cne
    (Get-CollectionHash $comparison.fingerprints)) { throw 'Drift: migration held.' }
$candidate | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath .\receipt.reconciled.json -NoClobber
```

Both helpers reject missing/duplicate IDs or ownership mismatches. If original
provenance or exact fingerprint equality cannot be proved, do not upgrade and
do not clean up; reconcile the drift explicitly with the owner. A reconciled
receipt does not authorize deletion. Preview and actual cleanup still require
separate approval. **Legacy deployment cleanup stays held until private original
receipt migration proof exists.** This revision does not migrate private files
or touch the live agent, DCR or two associations.

Successful collection is an intended operational baseline and remains enabled.
There is recurring Log Analytics ingestion/retention cost: one sample per
logical disk instance per minute per node, including `_Total` where emitted.
No alert evaluation cost is introduced by this module.

Tests: `pwsh .\tests\Test-Collection.ps1`.

References:
- https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-performance
- https://learn.microsoft.com/azure/templates/microsoft.insights/2023-03-11/datacollectionrules
- https://learn.microsoft.com/azure/templates/microsoft.insights/2023-03-11/datacollectionruleassociations
