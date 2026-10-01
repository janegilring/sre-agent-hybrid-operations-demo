#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$WorkspaceResourceId,
    [Parameter(Mandatory)][string]$TargetsPath,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ReceiptPath
)
. "$PSScriptRoot\Common.ps1"
$inputs = Read-Inputs $SubscriptionId $WorkspaceResourceId $TargetsPath $ConfigPath
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
Assert-Receipt $receipt $SubscriptionId $ResourceGroup
if ($receipt.state -ne 'created' -or @($receipt.createdRuleIds).Count -ne 5) { throw 'Receipt does not prove all five rules were created.' }
$rules = @(Get-RuleInventory $SubscriptionId $ResourceGroup)
$thresholds = @{heartbeat=0; cpu=$inputs.Config.cpuThresholdPercent; memory=$inputs.Config.memoryAvailableThresholdPercent; disk=$inputs.Config.diskFreeThresholdPercent; coverage=0}
foreach ($name in $script:Suffixes) {
    $rule = @($rules | Where-Object name -EQ "$($inputs.Config.namePrefix)-$name")
    if ($rule.Count -ne 1 -or $rule[0].id -notin $receipt.createdRuleIds -or $rule[0].tags.'hybrid-monitoring-owner' -ne $receipt.ownerToken) { throw "Missing/foreign rule: $name" }
    $p = $rule[0].properties
    if (-not $p.enabled -or $p.scopes.Count -ne 1 -or $p.scopes[0] -ne $WorkspaceResourceId) { throw "Disabled or misconfigured rule: $name. Disabled is not delivered monitoring." }
    # GET may omit autoMitigate or return its default; resolveConfiguration is the selected contract.
    $resolveProperty = $p.PSObject.Properties['resolveConfiguration']
    if ($null -eq $resolveProperty -or $null -eq $resolveProperty.Value) { throw "Missing recovery configuration: $name" }
    $resolve = $resolveProperty.Value
    $autoResolved = $resolve.PSObject.Properties['autoResolved']
    $timeToResolve = $resolve.PSObject.Properties['timeToResolve']
    if ($null -eq $autoResolved -or $autoResolved.Value -isnot [bool] -or -not $autoResolved.Value -or
        $null -eq $timeToResolve -or $timeToResolve.Value -ne "PT$($inputs.Config.recoveryMinutes)M") {
        throw "Recovery configuration drift: $name"
    }
    $condition = $p.criteria.allOf[0]
    $operator = if ($name -in @('memory','disk')) { 'LessThan' } else { 'GreaterThan' }
    if ($p.criteria.allOf.Count -ne 1 -or $condition.threshold -ne $thresholds[$name] -or $condition.operator -ne $operator -or
        $condition.timeAggregation -ne 'Maximum' -or $condition.metricMeasureColumn -ne 'Value' -or $condition.resourceIdColumn -ne '_ResourceId' -or
        $p.evaluationFrequency -ne "PT$($inputs.Config.frequencyMinutes)M" -or $p.windowSize -ne "PT$($inputs.Config.sustainedMinutes)M" -or
        $p.overrideQueryTimeRange -ne 'PT1H') {
        throw "Rule condition or timing drift: $name"
    }
    $dimensionNames = @($condition.dimensions | ForEach-Object name)
    if ($dimensionNames.Count -ne 3 -or @(@('_ResourceId','InstanceName','Signal') | Where-Object { $_ -notin $dimensionNames }).Count) { throw "Dimension drift: $name" }
    foreach ($dimension in $condition.dimensions) {
        if ($dimension.operator -ne 'Include' -or $dimension.values.Count -ne 1 -or $dimension.values[0] -ne '*') { throw "Dimension filter drift: $name" }
    }
    $expectedQuery = (Expand-Query $inputs $name).Replace("`r`n","`n").Trim()
    if ($p.criteria.allOf[0].query.Replace("`r`n","`n").Trim() -ne $expectedQuery) { throw "Canonical query drift: $name" }
}
$work = New-WorkDirectory
try { Test-LiveCoverage $inputs $work }
finally { Remove-Item -LiteralPath $work -Recurse -Force }
Write-Host 'PASS: five owned enabled rules and live telemetry coverage. This does not prove incident routing or recovery.'
