#requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-AzJson {
    param([string[]]$Arguments)
    $text = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: $($Arguments[0..([Math]::Min(2,$Arguments.Count-1))] -join ' ')" }
    if ($text) { ($text -join "`n") | ConvertFrom-Json -Depth 100 }
}

function Read-StarterParameters {
    param([string]$Path)
    if ([IO.Path]::GetExtension($Path) -eq '.bicepparam') {
        $text = & bicep build-params $Path --stdout
        if ($LASTEXITCODE -ne 0) { throw 'Bicep parameter compilation failed.' }
        $compiled = ($text -join "`n") | ConvertFrom-Json -AsHashtable
        $document = if ($compiled.ContainsKey('parametersJson')) {
            $compiled.parametersJson | ConvertFrom-Json -AsHashtable
        } else { $compiled }
    } else {
        $document = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable
    }
    $values = @{}
    foreach ($entry in $document.parameters.GetEnumerator()) {
        if (!$entry.Value.ContainsKey('value')) { throw "Only literal parameter values are supported: $($entry.Key)" }
        $values[$entry.Key] = $entry.Value.value
    }
    $allowed = @('agentName','location','targetResourceGroupNames','ownershipToken','grantTargetReader','agentAccessUserObjectIds')
    foreach ($key in $values.Keys) { if ($key -notin $allowed) { throw "Unknown parameter: $key" } }
    if ($values.agentName -notmatch '^[A-Za-z][-A-Za-z0-9]{0,30}[A-Za-z0-9]$') { throw 'Invalid agentName.' }
    if ($values.location -notmatch '^[a-z0-9]+$') { throw 'Supply an Azure location name.' }
    if (!$values.ContainsKey('grantTargetReader')) { $values.grantTargetReader = $false }
    if ($values.grantTargetReader -isnot [bool]) { throw 'grantTargetReader must be Boolean.' }
    if (!$values.ContainsKey('agentAccessUserObjectIds')) { $values.agentAccessUserObjectIds = @() }
    if ($values.agentAccessUserObjectIds -isnot [array]) { throw 'agentAccessUserObjectIds must be an array.' }
    foreach ($id in $values.agentAccessUserObjectIds) {
        $parsed = [guid]::Empty
        if (![guid]::TryParse($id, [ref]$parsed) -or $parsed -eq [guid]::Empty) { throw 'User object IDs must be explicit nonempty GUIDs.' }
    }
    if ($values.targetResourceGroupNames -isnot [array] -or !$values.targetResourceGroupNames.Count) { throw 'Supply target RG names.' }
    foreach ($rg in $values.targetResourceGroupNames) {
        if ($rg -notmatch '^[A-Za-z0-9_().-]{1,90}$' -or $rg.EndsWith('.')) { throw "Invalid target RG name: $rg" }
    }
    foreach ($key in @('targetResourceGroupNames','agentAccessUserObjectIds')) {
        if (@($values[$key] | Sort-Object -Unique).Count -ne $values[$key].Count) { throw "Duplicate values in $key." }
    }
    return $values
}

function Get-OwnedIds {
    param([string]$SubscriptionId,[string]$ResourceGroup,[string]$AgentName)
    $base = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers"
    @(
        "$base/Microsoft.App/agents/$AgentName"
        "$base/Microsoft.Insights/components/$AgentName-insights"
        "$base/Microsoft.OperationalInsights/workspaces/$AgentName-logs"
        "$base/Microsoft.ManagedIdentity/userAssignedIdentities/$AgentName-identity"
    )
}

function Assert-NewResources {
    param([string]$SubscriptionId,[string]$ResourceGroup,[hashtable]$Values)
    $existing = @(Invoke-AzJson @('resource','list','--subscription',$SubscriptionId,'--resource-group',$ResourceGroup))
    foreach ($id in (Get-OwnedIds $SubscriptionId $ResourceGroup $Values.agentName)) {
        if ($id -in @($existing | ForEach-Object id)) { throw "Refusing to overwrite existing resource: $id" }
    }
    foreach ($rg in $Values.targetResourceGroupNames) {
        $null = Invoke-AzJson @('group','show','--subscription',$SubscriptionId,'--name',$rg)
    }
}

function Assert-Subnet {
    param([string]$SubnetId,[string]$Location,[string]$SubscriptionId)
    if (!$SubnetId) { return }
    if ($SubnetId -notmatch "^/subscriptions/$([regex]::Escape($SubscriptionId))/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$") {
        throw 'Subnet must be an exact resource ID in the selected subscription.'
    }
    $subnet = Invoke-AzJson @('resource','show','--ids',$SubnetId,'--api-version','2024-05-01','--subscription',$SubscriptionId)
    $vnetId = $SubnetId.Substring(0,$SubnetId.LastIndexOf('/subnets/'))
    $vnet = Invoke-AzJson @('resource','show','--ids',$vnetId,'--api-version','2024-05-01','--subscription',$SubscriptionId)
    $p = $subnet.properties | ConvertTo-Json -Depth 30 | ConvertFrom-Json -AsHashtable
    $prefixes = @(@($p['addressPrefix']) + @($p['addressPrefixes']) | Where-Object { $_ })
    $invalidPrefixes = @($prefixes | Where-Object {
        $_ -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/(\d{1,2})$' -or
        [int]($_.Split('/')[-1]) -gt 27 -or
        @($_.Split('/')[0].Split('.') | Where-Object { [int]$_ -gt 255 }).Count
    })
    if ($vnet.location -ne $Location -or !$prefixes.Count -or $invalidPrefixes.Count) {
        throw 'Subnet must be same-region IPv4 /27 or larger.'
    }
    $delegations = @($p['delegations'] | Where-Object { $_ -and $_['properties'] } | ForEach-Object { $_['properties']['serviceName'] })
    if ('Microsoft.App/environments' -notin $delegations) { throw 'Missing Microsoft.App/environments delegation.' }
    if (@($p['ipConfigurations'] | Where-Object { $_ }).Count -or @($p['privateEndpoints'] | Where-Object { $_ }).Count) { throw 'Subnet is in use.' }
    Write-Warning 'Preflight only: confirm dedicated ownership, routes, DNS, NSG and capacity; subnet is NOT attached by this template.'
}
