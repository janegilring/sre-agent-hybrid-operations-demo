#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CollectionAz {
    param([string[]]$Arguments)
    $text = & az @Arguments --only-show-errors --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (($text -join "`n") -match '(?m)^ERROR: \((ResourceNotFound|NotFound)\)') { Write-Error 'Resource absent (404).' -ErrorId CollectionResourceNotFound }
        throw "Azure CLI failed: $($Arguments[0..1] -join ' ')"
    }
    if ($text) { ($text -join "`n") | ConvertFrom-Json -Depth 100 }
}

function Get-CollectionResource {
    param([string]$SubscriptionId, [string]$Id, [string]$ApiVersion = '2023-03-11')
    Invoke-CollectionAz @('rest','--subscription',$SubscriptionId,'--method','get','--url',"https://management.azure.com${Id}?api-version=$ApiVersion")
}

function Get-CollectionList {
    param([string]$SubscriptionId, [string]$Id, [string]$ApiVersion = '2023-03-11')
    $url = "https://management.azure.com${Id}?api-version=$ApiVersion"
    do {
        $response = Invoke-CollectionAz @('rest','--subscription',$SubscriptionId,'--method','get','--url',$url)
        $response.value
        $url = if ($response.PSObject.Properties.Name -contains 'nextLink') { $response.nextLink } else { $null }
    } while ($url)
}

function Get-CollectionHash {
    param($Object)
    function ConvertTo-Canonical($Value) {
        if ($Value -is [System.Collections.IDictionary]) {
            $result = [ordered]@{}
            [string[]]$keys = @($Value.Keys)
            [Array]::Sort($keys, [StringComparer]::Ordinal)
            foreach ($key in $keys) { $result[$key] = ConvertTo-Canonical $Value[$key] }
            return $result
        }
        if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-Canonical $_ }) }
        return $Value
    }
    $data = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Object -Depth 100) -AsHashtable -Depth 100
    $json = ConvertTo-Json -InputObject (ConvertTo-Canonical $data) -Depth 100 -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))
}

function Assert-CollectionReceipt {
    param($Receipt, [switch]$WithoutFingerprints)
    $guid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    if ($Receipt.subscriptionId -notmatch "^$guid\z" -or $Receipt.ownerToken -notmatch "^$guid\z" -or
        $Receipt.resourceGroup -notmatch '^[a-z0-9_()-][a-z0-9_.()-]{0,89}\z' -or $Receipt.resourceGroup.EndsWith('.') -or
        $Receipt.name -notmatch '^nic-disk-[a-z0-9-]+\z') { throw 'Invalid ownership receipt scope.' }
    $root = "/subscriptions/$($Receipt.subscriptionId)/resourceGroups/$($Receipt.resourceGroup)"
    if ($Receipt.dcrId -ine "$root/providers/Microsoft.Insights/dataCollectionRules/$($Receipt.name)") { throw 'Invalid DCR scope.' }
    $expected = @($Receipt.machineIds | ForEach-Object {
        if ($_ -notmatch "^$([regex]::Escape($root))/providers/Microsoft.HybridCompute/machines/[a-z0-9_-][a-z0-9_.-]*\z") { throw 'Invalid machine scope.' }
        "$_/providers/Microsoft.Insights/dataCollectionRuleAssociations/$($Receipt.name)"
    })
    foreach ($set in @(@{actual=@($Receipt.machineIds);expected=@($Receipt.machineIds)}, @{actual=@($Receipt.associationIds);expected=$expected})) {
        if ($set.actual.Count -ne 2 -or @($set.actual | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -ne 2 -or
            @($set.actual | Where-Object { $_ -notin $set.expected }).Count) { throw 'Invalid or duplicate receipt IDs.' }
    }
    if (-not $WithoutFingerprints) {
        $ids = @($Receipt.associationIds) + @($Receipt.dcrId)
        if ($Receipt.fingerprintVersion -ne 1 -or @($Receipt.fingerprints).Count -ne 3) { throw 'Original deployment fingerprints required.' }
        foreach ($id in $ids) {
            $entry = @($Receipt.fingerprints | Where-Object id -EQ $id)
            if ($entry.Count -ne 1 -or $entry[0].sha256 -cnotmatch '^[A-F0-9]{64}\z') { throw 'Invalid deployment fingerprints.' }
        }
    }
}

function Get-CollectionFingerprint {
    param($Resource)
    $data = ConvertTo-Json -InputObject $Resource -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
    # These fields describe provider lifecycle/auditing, not owned configuration.
    $null = $data.Remove('etag'); $null = $data.Remove('systemData')
    $null = $data.properties.Remove('provisioningState')
    $data.id = $data.id.ToLowerInvariant()
    Get-CollectionHash $data
}

function Assert-CollectionOwnership {
    param($Receipt, $Resource, [string]$Id)
    if ($Resource.id -ine $Id) { throw 'Resource identity mismatch.' }
    if ($Id -ieq $Receipt.dcrId) {
        if ($Resource.tags.ownerToken -cne $Receipt.ownerToken -or $Resource.tags.component -cne 'hybrid-monitoring-collection') { throw 'DCR ownership mismatch.' }
    } elseif ($Resource.properties.dataCollectionRuleId -ine $Receipt.dcrId -or
        $Resource.properties.description -cne "hybrid-monitoring-collection ownerToken=$($Receipt.ownerToken)") { throw 'Association ownership mismatch.' }
}

function New-CollectionReceipt {
    param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][object[]]$OriginalDeploymentSnapshots)
    Assert-CollectionReceipt $Receipt -WithoutFingerprints
    if ($OriginalDeploymentSnapshots.Count -ne 3) { throw 'Exactly three original deployment GET snapshots required.' }
    $result = $Receipt | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
    $result.fingerprintVersion = 1
    $result.fingerprints = @(
        foreach ($id in @($Receipt.associationIds) + @($Receipt.dcrId)) {
            $snapshot = @($OriginalDeploymentSnapshots | Where-Object id -EQ $id)
            if ($snapshot.Count -ne 1) { throw 'Missing or duplicate original snapshot.' }
            Assert-CollectionOwnership $Receipt $snapshot[0] $id
            @{id=$id;sha256=(Get-CollectionFingerprint $snapshot[0])}
        }
    )
    Assert-CollectionReceipt $result
    [pscustomobject]$result
}

function Assert-CollectionWhatIf {
    param($WhatIf, [string[]]$ExpectedIds)
    if ($WhatIf.status -ne 'Succeeded' -or $ExpectedIds.Count -ne 3 -or @($ExpectedIds | Select-Object -Unique).Count -ne 3) { throw 'Invalid what-if status or expected IDs.' }
    $changes = @($WhatIf.changes | Where-Object changeType -ne 'Ignore')
    if ($changes.Count -ne 3) { throw "Expected exactly three creates; got $($changes.Count) changes." }
    foreach ($change in $changes) {
        if ($change.changeType -ne 'Create' -or $change.resourceId -notin $ExpectedIds) { throw "Unsafe change: $($change.changeType) $($change.resourceId)" }
    }
    if (@($changes.resourceId | Select-Object -Unique).Count -ne 3) { throw 'Duplicate what-if resource.' }
}

function Assert-NoDiskCollection {
    param([object[]]$Rules)
    foreach ($rule in $Rules) {
        $properties = $rule.properties
        if ($properties.PSObject.Properties.Name -notcontains 'dataSources') { continue }
        if ($properties.dataSources.PSObject.Properties.Name -notcontains 'performanceCounters') { continue }
        foreach ($counter in $properties.dataSources.performanceCounters) {
            foreach ($specifier in $counter.counterSpecifiers) {
                # Conservative: do not add a duplicate even if an existing destination differs.
                if ($specifier -match '(?i)Logical\s*Disk.*(Free\s*Space|\*)') { throw "Existing disk collection requires reconciliation: $($rule.id) $specifier" }
            }
        }
    }
}
