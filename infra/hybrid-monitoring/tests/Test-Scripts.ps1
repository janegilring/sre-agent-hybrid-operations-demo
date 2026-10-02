#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\Common.ps1"
$failures = @()
Get-ChildItem "$PSScriptRoot\.." -Filter *.ps1 -Recurse | ForEach-Object {
    $tokens=$null; $errors=$null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    $failures += $errors
}
if ($failures.Count) { throw ($failures | Out-String) }
function Must-Fail([scriptblock]$Action, [string]$MessagePattern = '.') {
    $failed=$false
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $MessagePattern) { throw }
        $failed=$true
    }
    if (-not $failed) { throw 'Expected failure was accepted.' }
}
$inputs = @{
    Targets=@([pscustomobject]@{resourceId='/A'; totalMemoryMiB=16384; disks=@('C:','D:')})
    Config=(Get-Content "$PSScriptRoot\..\config.example.json" -Raw | ConvertFrom-Json -AsHashtable)
}
foreach ($name in $script:Suffixes) {
    $q = Expand-Query $inputs $name
    if ($q -match '__[A-Z_]+__') { throw "Unexpanded query: $name" }
    if ($q -match '\r?\n[ \t]*\r?\n') { throw "Portal current-query separator in expanded query: $name" }
    if (($q -split ';')[-1].Trim() -notmatch '^(Inventory|Expected|Perf)\b') { throw "Missing final tabular expression: $name" }
}
$h = @([pscustomobject]@{_ResourceId='/a'; Signal='Heartbeat'; InstanceName=''; LastSeen='2026-01-01'; Value=0})
$c = @(
    [pscustomobject]@{_ResourceId='/A'; Signal='CPU'; InstanceName='_Total'; LastSeen='2026-01-01'; Value=0},
    [pscustomobject]@{_ResourceId='/a'; Signal='Memory'; InstanceName=''; LastSeen='2026-01-01'; Value=0},
    [pscustomobject]@{_ResourceId='/a'; Signal='Disk'; InstanceName='C:'; LastSeen='2026-01-01'; Value=0},
    [pscustomobject]@{_ResourceId='/a'; Signal='Disk'; InstanceName='D:'; LastSeen='2026-01-01'; Value=0}
)
Assert-CoverageRows $inputs $h $c
Must-Fail { Assert-CoverageRows $inputs @() @() }
Must-Fail { Assert-CoverageRows $inputs $h $c[0..2] }
$c[0].Value=1
Must-Fail { Assert-CoverageRows $inputs $h $c }
$c[0].Value=0
Must-Fail { Assert-CoverageRows $inputs $h (@($c)+@($c[0])) }
# Stub native az: an error must never turn into an empty successful query.
function az { $global:LASTEXITCODE=7; return '{}' }
Must-Fail { Invoke-AzJson @('rest','--method','get') }
Remove-Item Function:\az
$receipt = [pscustomobject]@{
    schemaVersion=1; subscriptionId='test'; resourceGroup='rg'; namePrefix='test'
    ownerToken='11111111-1111-1111-1111-111111111111'
    createdRuleIds=@('/subscriptions/test/resourceGroups/rg/providers/Microsoft.Insights/scheduledQueryRules/test-cpu')
}
Assert-Receipt $receipt test rg
Must-Fail { Assert-Receipt $receipt other rg }
$receipt.createdRuleIds=@('/subscriptions/test/resourceGroups/rg')
Must-Fail { Assert-Receipt $receipt test rg }
$work = New-WorkDirectory
try {
    $sub='11111111-1111-1111-1111-111111111111'
    $targetId="/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.HybridCompute/machines/host"
    $workspaceId="/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/logs"
    $targetsPath=Join-Path $work 'targets.json'
    $receiptPath=Join-Path $work 'receipt.json'
    ConvertTo-Json -InputObject @(@{resourceId=$targetId; totalMemoryMiB=16384; disks=@('C:')}) | Set-Content $targetsPath
    $configPath="$PSScriptRoot\..\config.example.json"
    $validated=Read-Inputs $sub $workspaceId $targetsPath $configPath
    if ($validated.Targets.Count -ne 1) { throw 'Single-target array was lost.' }
    Must-Fail { Read-Inputs '00000000-0000-0000-0000-000000000000' $workspaceId $targetsPath $configPath }
    $global:HmTestCalls=[System.Collections.Generic.List[string]]::new()
    $global:HmTestForeign=$false
    $global:HmTestRules=$null
    function az {
        $global:LASTEXITCODE=0
        $a=@($args)
        $global:HmTestCalls.Add(($a -join ' '))
        if ($a[0] -eq 'bicep') {
            '{}' | Set-Content $a[([array]::IndexOf($a,'--outfile')+1)] -WhatIf:$false -Confirm:$false
            return
        }
        if ($a[0] -eq 'deployment') { return '{"changes":[]}' }
        $url=$a[([array]::IndexOf($a,'--url')+1)]
        if ($url -like '*scheduledQueryRules*') {
            if ($null -ne $global:HmTestRules) {
                return (@{value=$global:HmTestRules} | ConvertTo-Json -Depth 30 -Compress)
            }
            if ($global:HmTestForeign) {
                return (@{value=@(@{id="/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Insights/scheduledQueryRules/hybrid-windows-cpu"; name='hybrid-windows-cpu'; tags=@{'hybrid-monitoring-owner'='foreign'}})} | ConvertTo-Json -Depth 10 -Compress)
            }
            return '{"value":[]}'
        }
        if ($url -like '*api.loganalytics*') {
            $body=$a[([array]::IndexOf($a,'--body')+1)].Substring(1)
            $query=(Get-Content $body -Raw | ConvertFrom-Json).query
            $columns=@('TimeGenerated','_ResourceId','Signal','InstanceName','LastSeen','Value') | ForEach-Object { @{name=$_;type='string'} }
            $rows = @()
            if ($query -match 'let Recent = Heartbeat') {
                $rows += ,@('now',$targetId,'Heartbeat','','now',0)
            } elseif ($query -match 'let Expected = union') {
                $rows += ,@('now',$targetId,'CPU','_total','now',0)
                $rows += ,@('now',$targetId,'Memory','','now',0)
                $rows += ,@('now',$targetId,'Disk','c:','now',0)
            }
            return (@{tables=@(@{name='PrimaryResult';columns=@($columns);rows=@($rows)})} | ConvertTo-Json -Depth 20 -Compress)
        }
        return '{"properties":{"customerId":"11111111-1111-1111-1111-111111111111"}}'
    }
    $deployment=@{
        SubscriptionId=$sub; ResourceGroup='rg'; WorkspaceResourceId=$workspaceId
        TargetsPath=$targetsPath; ConfigPath=$configPath; ReceiptPath=$receiptPath
    }
    & "$PSScriptRoot\..\Deploy.ps1" @deployment -Apply -WhatIf
    if ($global:HmTestCalls.Where({$_ -match 'deployment group create|--method delete'}).Count -or (Test-Path $receiptPath)) { throw 'WhatIf mutated Azure or ownership.' }
    if (-not $global:HmTestCalls.Where({$_ -match 'deployment group validate'}).Count -or -not $global:HmTestCalls.Where({$_ -match 'deployment group what-if'}).Count) { throw 'Preview skipped ARM validation/what-if.' }
    $global:HmTestForeign=$true
    Must-Fail { & "$PSScriptRoot\..\Deploy.ps1" @deployment }
    $receipt=[ordered]@{
        schemaVersion=1; subscriptionId=$sub; resourceGroup='rg'; namePrefix='hybrid-windows'
        ownerToken=$sub; state='created'
        createdRuleIds=@("/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Insights/scheduledQueryRules/hybrid-windows-cpu")
    }
    $receipt | ConvertTo-Json | Set-Content $receiptPath
    Must-Fail { & "$PSScriptRoot\..\Cleanup.ps1" -SubscriptionId $sub -ResourceGroup rg -ReceiptPath $receiptPath -Confirm:$false }
    if ($global:HmTestCalls.Where({$_ -match '--method delete'}).Count) { throw 'Foreign cleanup was attempted.' }
    $global:HmTestForeign=$false
    $global:HmTestRules=@(foreach ($name in $script:Suffixes) {
        $threshold = switch ($name) {
            cpu { $validated.Config.cpuThresholdPercent }
            memory { $validated.Config.memoryAvailableThresholdPercent }
            disk { $validated.Config.diskFreeThresholdPercent }
            default { 0 }
        }
        @{
            id="/subscriptions/$sub/resourceGroups/rg/providers/Microsoft.Insights/scheduledQueryRules/hybrid-windows-$name"
            name="hybrid-windows-$name"; tags=@{'hybrid-monitoring-owner'=$sub}
            properties=@{
                enabled=$true; scopes=@($workspaceId)
                evaluationFrequency='PT5M'; windowSize='PT15M'; overrideQueryTimeRange='PT1H'
                resolveConfiguration=@{autoResolved=$true;timeToResolve='PT10M'}
                criteria=@{allOf=@(@{
                    threshold=$threshold; operator=$(if ($name -in @('memory','disk')) {'LessThan'} else {'GreaterThan'})
                    timeAggregation='Maximum'; metricMeasureColumn='Value'; resourceIdColumn='_ResourceId'
                    query=(Expand-Query $validated $name)
                    dimensions=@(foreach ($dimension in @('_ResourceId','InstanceName','Signal')) {
                        @{name=$dimension;operator='Include';values=@('*')}
                    })
                })}
            }
        }
    })
    $receipt.createdRuleIds=@($global:HmTestRules | ForEach-Object { $_.id })
    $receipt | ConvertTo-Json -Depth 10 | Set-Content $receiptPath
    $baseline=$global:HmTestRules | ConvertTo-Json -Depth 30
    $receiptHash=(Get-FileHash -LiteralPath $receiptPath).Hash
    $previewPath=Join-Path $work 'cleanup-preview.txt'
    $null=Start-Transcript -LiteralPath $previewPath
    try {
        & "$PSScriptRoot\..\Cleanup.ps1" -SubscriptionId $sub -ResourceGroup rg -ReceiptPath $receiptPath -WhatIf
    } finally {
        $null=Stop-Transcript
    }
    $preview=Get-Content -LiteralPath $previewPath -Raw
    if ([regex]::Matches($preview,'Delete this manifest-recorded owned alert rule only').Count -ne 5) { throw 'Cleanup WhatIf did not preview all five owned deletions.' }
    foreach ($id in $receipt.createdRuleIds) {
        if (-not $preview.Contains($id)) { throw "Cleanup WhatIf omitted owned rule: $id" }
    }
    if ($global:HmTestCalls.Where({$_ -match '--method delete'}).Count -or (Get-FileHash -LiteralPath $receiptPath).Hash -ne $receiptHash) { throw 'Cleanup WhatIf changed Azure or the receipt.' }
    # Mock GET representations must work under Common.ps1's StrictMode.
    foreach ($representation in @('absent','null','default')) {
        $global:HmTestRules=$baseline | ConvertFrom-Json -AsHashtable
        foreach ($rule in $global:HmTestRules) {
            if ($representation -eq 'null') { $rule.properties.autoMitigate=$null }
            if ($representation -eq 'default') { $rule.properties.autoMitigate=$true }
        }
        & "$PSScriptRoot\..\Validate.ps1" @deployment
    }
    $mutations=@(
        @{change={param($r) $r.properties.Remove('resolveConfiguration')}; error='Missing recovery configuration'},
        @{change={param($r) $r.properties.autoMitigate=$true; $r.properties.Remove('resolveConfiguration')}; error='Missing recovery configuration'},
        @{change={param($r) $r.properties.resolveConfiguration=$null}; error='Missing recovery configuration'},
        @{change={param($r) $r.properties.resolveConfiguration.Remove('autoResolved')}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.autoResolved=$null}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.autoResolved=$false}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.autoResolved='true'}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.Remove('timeToResolve')}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.timeToResolve=$null}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.resolveConfiguration.timeToResolve='PT5M'}; error='Recovery configuration drift'},
        @{change={param($r) $r.properties.enabled=$false}; error='Disabled or misconfigured'},
        @{change={param($r) $r.properties.scopes=@('/foreign')}; error='Disabled or misconfigured'},
        @{change={param($r) $r.properties.scopes=@($workspaceId,'/extra')}; error='Disabled or misconfigured'},
        @{change={param($r) $r.name='foreign'}; error='Missing/foreign rule'},
        @{change={param($r) $r.id='/foreign'}; error='Missing/foreign rule'},
        @{change={param($r) $r.tags.'hybrid-monitoring-owner'='foreign'}; error='Missing/foreign rule'}
    )
    foreach ($index in 0..4) {
        foreach ($mutation in $mutations) {
            $global:HmTestRules=$baseline | ConvertFrom-Json -AsHashtable
            $null = & $mutation.change $global:HmTestRules[$index]
            Must-Fail { & "$PSScriptRoot\..\Validate.ps1" @deployment } $mutation.error
        }
    }
} finally {
    Remove-Item Function:\az -ErrorAction SilentlyContinue
    Remove-Item $work -Recurse -Force
    Remove-Variable HmTestCalls,HmTestForeign,HmTestRules -Scope Global -ErrorAction SilentlyContinue
}
Write-Host 'PASS: parse, substitution, exact coverage, CLI failure, receipt scope, WhatIf, foreign ownership and five-rule GET recovery validation tests.'
