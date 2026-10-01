#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_.()-]+$')][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$WorkspaceResourceId,
    [Parameter(Mandatory)][string]$TargetsPath,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ReceiptPath,
    [switch]$Apply
)
. "$PSScriptRoot\Common.ps1"
$inputs = Read-Inputs $SubscriptionId $WorkspaceResourceId $TargetsPath $ConfigPath
if (Test-Path -LiteralPath $ReceiptPath) { throw 'Receipt already exists. Refuse to overwrite ownership history.' }
$token = [guid]::NewGuid().ToString()
$ids = @($script:Suffixes | ForEach-Object { "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/scheduledQueryRules/$($inputs.Config.namePrefix)-$_" })
$work = New-WorkDirectory
try {
    Test-LiveCoverage $inputs $work
    $existing = @(Get-RuleInventory $SubscriptionId $ResourceGroup)
    if (@($existing | Where-Object id -In $ids).Count) { throw 'Rule name already exists. No adoption or overwrite of existing rules is supported.' }
    $template = Join-Path $work 'main.json'
    $null = Invoke-AzJson @('bicep','build','--file',"$PSScriptRoot\main.bicep",'--outfile',$template)
    $parameters = @{}
    foreach ($key in $inputs.Config.Keys) { $parameters[$key] = @{value=$inputs.Config[$key]} }
    $parameters.targets = @{value=@($inputs.Targets)}
    $parameters.workspaceResourceId = @{value=$WorkspaceResourceId}
    $parameters.ownerToken = @{value=$token}
    $parameterPath = Join-Path $work 'parameters.json'
    @{parameters=$parameters} | ConvertTo-Json -Depth 30 | Set-Content $parameterPath -Encoding utf8 -WhatIf:$false -Confirm:$false
    $arguments = @('--subscription',$SubscriptionId,'--resource-group',$ResourceGroup,
        '--name',"hybrid-$token",'--template-file',$template,'--parameters',"@$parameterPath",'--mode','Incremental')
    $null = Invoke-AzJson (@('deployment','group','validate') + $arguments)
    $changes = Invoke-AzJson (@('deployment','group','what-if') + $arguments + @('--no-pretty-print'))
    $changes | ConvertTo-Json -Depth 30 | Out-Host
    Write-Host "Proposal: five rules; enabled=$($inputs.Config.enabled); exact workspace=$WorkspaceResourceId; $($inputs.Targets.Count) explicit targets."
    if (-not $Apply) { Write-Host 'Preview only. Nothing deployed; -Apply and ShouldProcess confirmation are required.'; return }
    if ($PSCmdlet.ShouldProcess(($ids -join ', '), 'Create five persistent monitoring rules after coverage, ARM validation and what-if')) {
        # Recheck immediately before mutation. Run installations serially; ARM does not offer create-only deployment.
        $existing = @(Get-RuleInventory $SubscriptionId $ResourceGroup)
        if (@($existing | Where-Object id -In $ids).Count) { throw 'A rule appeared during preview; refusing overwrite.' }
        $receipt = [ordered]@{
            schemaVersion=1; subscriptionId=$SubscriptionId; resourceGroup=$ResourceGroup
            namePrefix=$inputs.Config.namePrefix; ownerToken=$token; createdRuleIds=@()
            plannedRuleIds=$ids; state='applying'; recordedUtc=[datetime]::UtcNow.ToString('o')
        }
        $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8
        try {
            $null = Invoke-AzJson (@('deployment','group','create') + $arguments)
        } finally {
            # Capture partial creation too. If this read fails, receipt stays applying; no unsafe cleanup fallback.
            $owned = @(Get-RuleInventory $SubscriptionId $ResourceGroup | Where-Object {
                $_.id -in $ids -and $_.tags.'hybrid-monitoring-owner' -eq $token
            })
            $receipt.createdRuleIds = @($owned | ForEach-Object id)
            $receipt.state = if ($owned.Count -eq 5) { 'created' } else { 'partial' }
            $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8
        }
        if ($receipt.createdRuleIds.Count -ne 5) { throw 'Incomplete deployment; inspect receipt and clean up only verified owned IDs.' }
        & "$PSScriptRoot\Validate.ps1" -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -WorkspaceResourceId $WorkspaceResourceId -TargetsPath $TargetsPath -ConfigPath $ConfigPath -ReceiptPath $ReceiptPath
    }
} finally { Remove-Item -LiteralPath $work -Recurse -Force -WhatIf:$false -Confirm:$false }
