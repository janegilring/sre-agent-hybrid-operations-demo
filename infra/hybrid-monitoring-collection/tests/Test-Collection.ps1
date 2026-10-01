$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\Common.ps1"
$ids = @('/a','/b','/c')
$safe = @{status='Succeeded'; changes=@($ids | ForEach-Object { @{resourceId=$_;changeType='Create'} })}
Assert-CollectionWhatIf $safe $ids
foreach ($type in @('Modify','Delete','NoChange','Unsupported')) {
    $unsafe = @{status='Succeeded';changes=@(@{resourceId='/a';changeType=$type},@{resourceId='/b';changeType='Create'},@{resourceId='/c';changeType='Create'})}
    $rejected = $false
    try { Assert-CollectionWhatIf $unsafe $ids } catch { $rejected = $true }
    if (-not $rejected) { throw "Failed rejection: $type" }
}
$rejected = $false
try { Assert-CollectionWhatIf $safe @('/a','/b','/other') } catch { $rejected = $true }
if (-not $rejected) { throw 'Failed foreign ID rejection.' }
$rejected = $false
try { Assert-NoDiskCollection @([pscustomobject]@{id='/foreign';properties=[pscustomobject]@{dataSources=[pscustomobject]@{performanceCounters=@(@{counterSpecifiers=@('\LogicalDisk(C:)\% Free Space')})}}}) } catch { $rejected = $true }
if (-not $rejected) { throw 'Failed duplicate collection rejection.' }
Assert-NoDiskCollection @([pscustomobject]@{properties=[pscustomobject]@{dataSources=[pscustomobject]@{performanceCounters=@(@{counterSpecifiers=@('\Memory\Available Bytes')})}}})
'PASS: exact three-create guard, foreign-resource rejection, duplicate collection rejection.'

function Copy-Object($Value) { ConvertTo-Json -InputObject $Value -Depth 100 | ConvertFrom-Json -Depth 100 }
$subscription = '11111111-1111-1111-1111-111111111111'
$root = "/subscriptions/$subscription/resourceGroups/test"
$base = [pscustomobject]@{subscriptionId=$subscription;resourceGroup='test';name='nic-disk-test';ownerToken='22222222-2222-2222-2222-222222222222'
    dcrId="$root/providers/Microsoft.Insights/dataCollectionRules/nic-disk-test"
    machineIds=@("$root/providers/Microsoft.HybridCompute/machines/one","$root/providers/Microsoft.HybridCompute/machines/two")}
$base | Add-Member associationIds @($base.machineIds | ForEach-Object { "$_/providers/Microsoft.Insights/dataCollectionRuleAssociations/$($base.name)" })
$snapshots = @([pscustomobject]@{id=$base.dcrId;name=$base.name;type='Microsoft.Insights/dataCollectionRules';kind='Windows';location='northeurope'
    tags=@{ownerToken=$base.ownerToken;component='hybrid-monitoring-collection'}
    properties=@{provisioningState='Succeeded';dataSources=@{performanceCounters=@(@{counterSpecifiers=@('\LogicalDisk(*)\% Free Space')})}
        destinations=@{logAnalytics=@(@{name='workspace';workspaceResourceId="$root/providers/Microsoft.OperationalInsights/workspaces/original"})}
        dataFlows=@(@{streams=@('Microsoft-Perf');destinations=@('workspace')})}})
$snapshots += @($base.associationIds | ForEach-Object { [pscustomobject]@{id=$_;properties=@{dataCollectionRuleId=$base.dcrId;description="hybrid-monitoring-collection ownerToken=$($base.ownerToken)"}} })
$receipt = New-CollectionReceipt $base $snapshots
$reordered = [ordered]@{}
@($snapshots[0].PSObject.Properties) | Sort-Object Name -Descending | ForEach-Object { $reordered[$_.Name] = $_.Value }
if ((Get-CollectionFingerprint $reordered) -cne $receipt.fingerprints[2].sha256) { throw 'Reordered resource changed fingerprint.' }
if ((Get-CollectionHash ('{"b":[{"z":2,"a":1}],"a":0}' | ConvertFrom-Json)) -cne
    (Get-CollectionHash ('{"a":0,"b":[{"a":1,"z":2}]}' | ConvertFrom-Json))) { throw 'Noncanonical property ordering.' }
$volatile = Copy-Object $snapshots[0]
$volatile | Add-Member etag 'new'
$volatile | Add-Member systemData @{lastModifiedAt='later'}
$volatile.properties.provisioningState = 'Updating'
if ((Get-CollectionFingerprint $volatile) -cne $receipt.fingerprints[2].sha256) { throw 'Volatile metadata changed fingerprint.' }
$fixture = Join-Path $PSScriptRoot ".receipt-test-$([guid]::NewGuid()).json"
$global:collectionTest = @{requests=[Collections.Generic.List[object]]::new();deleted=[Collections.Generic.List[string]]::new();provider=$null;ids=(@($base.associationIds) + @($base.dcrId))}
function az {
    $method = $args[[Array]::IndexOf($args,'--method')+1]
    $id = ([uri]$args[[Array]::IndexOf($args,'--url')+1]).AbsolutePath
    if ($id -notin $global:collectionTest.ids) { throw "Foreign ARM request: $id" }
    $global:collectionTest.requests.Add(@{method=$method;id=$id})
    $global:LASTEXITCODE = 0
    if ($method -eq 'delete') { $global:collectionTest.deleted.Add($id); return }
    if ($id -in $global:collectionTest.deleted) { $global:LASTEXITCODE = 1; return 'ERROR: (ResourceNotFound) Absent' }
    $global:collectionTest.provider | Where-Object id -EQ $id | ConvertTo-Json -Depth 100
}
function Test-Rejection($Candidate, $ProviderData, [int]$ExpectedRequests = -1) {
    $global:collectionTest.requests.Clear(); $global:collectionTest.deleted.Clear(); $global:collectionTest.provider = $ProviderData
    $Candidate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixture
    $rejected = $false
    try { & "$PSScriptRoot\..\Cleanup.ps1" -ReceiptPath $fixture -Confirm:$false } catch { $rejected = $true }
    if (-not $rejected -or $global:collectionTest.deleted.Count -ne 0 -or ($ExpectedRequests -ge 0 -and $global:collectionTest.requests.Count -ne $ExpectedRequests)) { throw 'Unsafe cleanup rejection.' }
}
try {
    Test-Rejection $base $snapshots 0
    foreach ($field in @('machineIds','associationIds')) {
        $bad = Copy-Object $receipt; $bad.$field[1] = $bad.$field[0].ToUpperInvariant()
        Test-Rejection $bad $snapshots 0
    }
    foreach ($alter in @(
        { param($r) $r.associationIds += '/foreign' },
        { param($r) $r.machineIds[0] += '?query' },
        { param($r) $r.resourceGroup = '../foreign' },
        { param($r) $r.subscriptionId = 'not-a-guid' },
        { param($r) $r.machineIds[0] += "`n" },
        { param($r) $r.dcrId += '/foreign' },
        { param($r) $r.fingerprints = @($r.fingerprints[0],$r.fingerprints[1]) },
        { param($r) $r.associationIds[1] = $r.associationIds[1].Replace('/two/','/foreign/') },
        { param($r) $r.fingerprints = @($r.fingerprints[0],$r.fingerprints[0],$r.fingerprints[2]) }
    )) { $bad = Copy-Object $receipt; & $alter $bad; Test-Rejection $bad $snapshots 0 }
    foreach ($alter in @(
        { param($s) $s[0].properties.dataSources.performanceCounters[0].counterSpecifiers += '\Processor(_Total)\% Processor Time' },
        { param($s) $s[0].properties.destinations.logAnalytics[0].workspaceResourceId += '-changed' },
        { param($s) $s[0].properties.destinations.logAnalytics[0].name = 'changed' },
        { param($s) $s[0].properties.dataFlows[0].destinations = @('changed') },
        { param($s) $s[0].tags.ownerToken = 'changed' },
        { param($s) $s[0].tags.component = 'changed' },
        { param($s) $s[0].tags | Add-Member foreignTag 'preserve-me' },
        { param($s) $s[0].location = 'westus' },
        { param($s) $s[0].kind = 'Linux' },
        { param($s) $s[2].properties.dataCollectionRuleId += '-changed' },
        { param($s) $s[2].properties.description += '-changed' }
    )) { $changed = Copy-Object $snapshots; & $alter $changed; Test-Rejection $receipt $changed }
    $global:collectionTest.requests.Clear(); $global:collectionTest.deleted.Clear(); $global:collectionTest.provider = Copy-Object $snapshots
    $receipt | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $fixture
    & "$PSScriptRoot\..\Cleanup.ps1" -ReceiptPath $fixture -WhatIf
    if ($global:collectionTest.requests.Count -ne 3 -or $global:collectionTest.deleted.Count) { throw 'What-if mutated resources.' }
    $global:collectionTest.requests.Clear()
    & "$PSScriptRoot\..\Cleanup.ps1" -ReceiptPath $fixture -Confirm:$false
    if (@($global:collectionTest.requests[0..2] | Where-Object method -NE 'get').Count) { throw 'Deleted before complete preflight.' }
    if ($global:collectionTest.requests.Count -ne 9 -or ($global:collectionTest.deleted -join ',') -cne ((@($receipt.associationIds) + @($receipt.dcrId)) -join ',')) { throw 'Selective cleanup/404 verification failed.' }
    'PASS: receipt validation, canonical fingerprints, configuration drift, all-before-delete, selective deletion and owned-only 404 verification.'
} finally { Remove-Item -LiteralPath $fixture -ErrorAction SilentlyContinue; Remove-Item Function:\az; Remove-Variable collectionTest -Scope Global }
