#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_.()-]+$')][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ReceiptPath
)
. "$PSScriptRoot\Common.ps1"
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
Assert-Receipt $receipt $SubscriptionId $ResourceGroup
if ($receipt.state -notin @('created','partial','cleaned')) { throw 'Unreconciled receipt: inspect exact planned IDs and ownership before any cleanup.' }
$rules = @(Get-RuleInventory $SubscriptionId $ResourceGroup)
foreach ($id in $receipt.createdRuleIds) {
    $rule = @($rules | Where-Object id -EQ $id)
    if ($rule.Count -and $rule[0].tags.'hybrid-monitoring-owner' -ne $receipt.ownerToken) { throw "Foreign ownership; refusing cleanup: $id" }
}
foreach ($id in $receipt.createdRuleIds) {
    if ($id -notin @($rules | ForEach-Object id)) { continue }
    if ($PSCmdlet.ShouldProcess($id, 'Delete this manifest-recorded owned alert rule only')) {
        $url = "https://management.azure.com${id}?api-version=2023-12-01"
        $current = Invoke-AzJson @('rest','--subscription',$SubscriptionId,'--method','get','--url',$url)
        if ($current.tags.'hybrid-monitoring-owner' -ne $receipt.ownerToken) { throw 'Ownership changed; stop cleanup.' }
        $null = Invoke-AzJson @('rest','--subscription',$SubscriptionId,'--method','delete','--url',$url)
    }
}
if (-not $WhatIfPreference) {
    $remaining = @(Get-RuleInventory $SubscriptionId $ResourceGroup | Where-Object id -In $receipt.createdRuleIds)
    if (-not $remaining.Count) {
        $receipt.state = 'cleaned'
        $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8
        Write-Host 'Owned rule deletion verified; workspace, collection, resource group and prior monitoring retained.'
    } else { throw 'Some owned rules remain (possibly confirmation declined); receipt retained.' }
}
