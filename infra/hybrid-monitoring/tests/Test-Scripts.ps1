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
function Must-Fail([scriptblock]$Action) {
    $failed=$false
    try { & $Action } catch { $failed=$true }
    if (-not $failed) { throw 'Expected failure was accepted.' }
}
$inputs = @{
    Targets=@([pscustomobject]@{resourceId='/A'; totalMemoryMiB=16384; disks=@('C:','D:')})
    Config=(Get-Content "$PSScriptRoot\..\config.example.json" -Raw | ConvertFrom-Json -AsHashtable)
}
foreach ($name in $script:Suffixes) {
    $q = Expand-Query $inputs $name
    if ($q -match '__[A-Z_]+__') { throw "Unexpanded query: $name" }
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
} finally {
    Remove-Item Function:\az -ErrorAction SilentlyContinue
    Remove-Item $work -Recurse -Force
    Remove-Variable HmTestCalls,HmTestForeign -Scope Global -ErrorAction SilentlyContinue
}
Write-Host 'PASS: parse, substitution, exact coverage, CLI failure, receipt scope, WhatIf and foreign ownership tests.'
