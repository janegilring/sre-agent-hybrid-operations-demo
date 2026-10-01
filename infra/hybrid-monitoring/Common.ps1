#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ModuleRoot = $PSScriptRoot
$script:Suffixes = @('heartbeat', 'cpu', 'memory', 'disk', 'coverage')

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $text = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed ($LASTEXITCODE): $($Arguments[0..1] -join ' '). No login or fallback attempted." }
    if (-not $text) { return $null }
    ($text -join "`n") | ConvertFrom-Json -Depth 100
}

function Read-Inputs {
    param([string]$SubscriptionId, [string]$WorkspaceResourceId, [string]$TargetsPath, [string]$ConfigPath)
    if ($SubscriptionId -notmatch '^[0-9a-fA-F-]{36}$' -or [guid]$SubscriptionId -eq [guid]::Empty) { throw 'Provide a real explicit subscription UUID.' }
    $root = "/subscriptions/$SubscriptionId/resourceGroups/"
    if ($WorkspaceResourceId -notmatch "^$([regex]::Escape($root))[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$") { throw 'Workspace must be an explicit ARM ID in the specified subscription.' }
    $config = Get-Content (Join-Path $script:ModuleRoot 'config.example.json') -Raw | ConvertFrom-Json -AsHashtable
    $overrides = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($key in $overrides.Keys) {
        if (-not $config.ContainsKey($key)) { throw "Unknown configuration field: $key" }
        $config[$key] = $overrides[$key]
    }
    if ($config.namePrefix -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,49}$') { throw 'Invalid namePrefix.' }
    if ($config.location -notmatch '^[a-z0-9]+$' -or $config.enabled -isnot [bool]) { throw 'Invalid location/enabled.' }
    foreach ($entry in @(
        @('frequencyMinutes', @(5,10,15)), @('sustainedMinutes', @(15,30)),
        @('recoveryMinutes', @(5,10,15)), @('memoryCounter', @('Available Bytes','Available MBytes'))
    )) {
        if ($config[$entry[0]] -notin $entry[1]) { throw "Invalid $($entry[0])." }
    }
    foreach ($entry in @(
        @('freshnessMinutes',5,30), @('ingestionLagMinutes',0,10), @('minSamplesPerBin',1,30),
        @('cpuThresholdPercent',1,100), @('memoryAvailableThresholdPercent',1,100), @('diskFreeThresholdPercent',1,100)
    )) {
        $v = $config[$entry[0]]
        if ($v -isnot [long] -and $v -isnot [int]) { throw "$($entry[0]) must be an integer." }
        if ($v -lt $entry[1] -or $v -gt $entry[2]) { throw "Invalid $($entry[0])." }
    }
    $targets = @(Get-Content -LiteralPath $TargetsPath -Raw | ConvertFrom-Json)
    if ($targets.Count -lt 1 -or $targets.Count -gt 50) { throw 'Explicit inventory requires 1–50 targets; no discovery fallback.' }
    $seen = @{}
    foreach ($target in $targets) {
        $id = [string]$target.resourceId
        if ($id -notmatch "^$([regex]::Escape($root))[^/]+/providers/Microsoft\.(HybridCompute/machines|Compute/virtualMachines)/[^/]+$" -or $id.Contains("'")) { throw "Invalid target ARM ID: $id" }
        if ($seen.ContainsKey($id)) { throw "Duplicate target: $id" }
        $seen[$id] = $true
        if (($target.totalMemoryMiB -isnot [long] -and $target.totalMemoryMiB -isnot [int]) -or $target.totalMemoryMiB -lt 1) { throw 'Each target needs verified physical totalMemoryMiB.' }
        if (@($target.disks).Count -lt 1) { throw 'Each target needs explicit required disk instances.' }
        $disks = @{}
        foreach ($disk in $target.disks) {
            if ($disk -isnot [string] -or [string]::IsNullOrWhiteSpace($disk) -or $disk -eq '_Total' -or $disk.Contains("'") -or $disks.ContainsKey($disk)) { throw 'Invalid/duplicate disk instance.' }
            $disks[$disk] = $true
        }
    }
    foreach ($id in $config.actionGroupIds) {
        if ($id -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Insights/actionGroups/[^/]+$') { throw 'Invalid action group ARM ID.' }
    }
    @{ SubscriptionId = $SubscriptionId; WorkspaceResourceId = $WorkspaceResourceId; Targets = $targets; Config = $config }
}

function Expand-Query {
    param($Inputs, [ValidateSet('heartbeat','cpu','memory','disk','coverage')][string]$Name)
    $query = (Get-Content (Join-Path $script:ModuleRoot 'queries\inventory.kql') -Raw) + "`n" +
        (Get-Content (Join-Path $script:ModuleRoot "queries\$Name.kql") -Raw)
    $replacements = @{
        '__TARGETS__' = ConvertTo-Json -InputObject @($Inputs.Targets) -Depth 20 -Compress
        '__FRESHNESS__' = $Inputs.Config.freshnessMinutes
        '__LAG__' = $Inputs.Config.ingestionLagMinutes
        '__SUSTAINED__' = $Inputs.Config.sustainedMinutes
        '__MIN_SAMPLES__' = $Inputs.Config.minSamplesPerBin
        '__MEMORY_COUNTER__' = $Inputs.Config.memoryCounter
    }
    foreach ($key in $replacements.Keys) { $query = $query.Replace($key, [string]$replacements[$key]) }
    $query
}

function New-WorkDirectory {
    $path = Join-Path $script:ModuleRoot ".work\$([guid]::NewGuid())"
    $null = New-Item -ItemType Directory -Path $path -Force -WhatIf:$false -Confirm:$false
    $path
}

function Invoke-LogQuery {
    param($Inputs, [string]$WorkspaceId, [string]$Query, [string]$WorkDirectory)
    $bodyPath = Join-Path $WorkDirectory 'query.json'
    @{query=$Query; timespan='PT1H'} | ConvertTo-Json -Depth 10 | Set-Content $bodyPath -Encoding utf8 -WhatIf:$false -Confirm:$false
    $result = Invoke-AzJson @('rest','--subscription',$Inputs.SubscriptionId,'--method','post',
        '--url',"https://api.loganalytics.azure.com/v1/workspaces/$WorkspaceId/query",
        '--resource','https://api.loganalytics.io','--body',"@$bodyPath")
    if ($result.PSObject.Properties.Name -contains 'error') { throw "Log query error/partial result: $($result.error.code)" }
    if (-not $result.tables -or $result.tables[0].name -ne 'PrimaryResult') { throw 'Missing primary query result.' }
    $table = $result.tables[0]
    foreach ($row in $table.rows) {
        $item = [ordered]@{}
        for ($i=0; $i -lt $table.columns.Count; $i++) { $item[$table.columns[$i].name] = $row[$i] }
        [pscustomobject]$item
    }
}

function Assert-CoverageRows {
    param($Inputs, [object[]]$Heartbeat, [object[]]$Coverage)
    $expected = @{}
    foreach ($target in $Inputs.Targets) {
        $id = $target.resourceId.ToLowerInvariant()
        $expected["$id|Heartbeat|"] = $true
        $expected["$id|CPU|_total"] = $true
        $expected["$id|Memory|"] = $true
        foreach ($disk in $target.disks) { $expected["$id|Disk|$($disk.ToLowerInvariant())"] = $true }
    }
    $observed = @{}
    foreach ($row in (@($Heartbeat) + @($Coverage))) {
        $key = "$($row._ResourceId.ToLowerInvariant())|$($row.Signal)|$($row.InstanceName.ToLowerInvariant())"
        if (-not $expected.ContainsKey($key) -or $observed.ContainsKey($key)) { throw "Unexpected or duplicate coverage row: $key" }
        $observed[$key] = $true
        if ($row.Value -ne 0 -or -not $row.LastSeen) { throw "Uncovered required signal: $key" }
    }
    if ($observed.Count -ne $expected.Count) { throw "Incomplete coverage: $($observed.Count)/$($expected.Count) required series." }
}

function Test-LiveCoverage {
    param($Inputs, [string]$WorkDirectory)
    $workspace = Invoke-AzJson @('rest','--subscription',$Inputs.SubscriptionId,'--method','get',
        '--url',"https://management.azure.com$($Inputs.WorkspaceResourceId)?api-version=2023-09-01")
    $workspaceId = $workspace.properties.customerId
    $heartbeat = @(Invoke-LogQuery $Inputs $workspaceId (Expand-Query $Inputs heartbeat) $WorkDirectory)
    $coverage = @(Invoke-LogQuery $Inputs $workspaceId (Expand-Query $Inputs coverage) $WorkDirectory)
    # Summary only: no raw guest logs or private counter values.
    @($heartbeat) + @($coverage) | Select-Object Signal, InstanceName, LastSeen, Value, _ResourceId | Format-Table -Wrap | Out-Host
    Assert-CoverageRows $Inputs $heartbeat $coverage
    foreach ($name in @('cpu','memory','disk')) {
        $null = @(Invoke-LogQuery $Inputs $workspaceId (Expand-Query $Inputs $name) $WorkDirectory)
    }
    Write-Host 'PASS: exact inventory and all required series covered; all five canonical queries executed.'
}

function Get-RuleInventory {
    param([string]$SubscriptionId, [string]$ResourceGroup)
    $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/scheduledQueryRules?api-version=2023-12-01"
    do {
        $response = Invoke-AzJson @('rest','--subscription',$SubscriptionId,'--method','get','--url',$url)
        $response.value
        $url = if ($response.PSObject.Properties.Name -contains 'nextLink') { $response.nextLink } else { $null }
    } while ($url)
}

function Assert-Receipt {
    param($Receipt, [string]$SubscriptionId, [string]$ResourceGroup)
    if ($Receipt.schemaVersion -ne 1 -or $Receipt.subscriptionId -ne $SubscriptionId -or $Receipt.resourceGroup -ne $ResourceGroup) { throw 'Receipt scope mismatch.' }
    if ($Receipt.ownerToken -notmatch '^[0-9a-f-]{36}$' -or $Receipt.namePrefix -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,49}$') { throw 'Invalid receipt ownership.' }
    $allowed = @($script:Suffixes | ForEach-Object { "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/scheduledQueryRules/$($Receipt.namePrefix)-$_" })
    foreach ($id in $Receipt.createdRuleIds) { if ($id -notin $allowed) { throw 'Receipt includes an out-of-scope rule.' } }
}
