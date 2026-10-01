#Requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param([Parameter(Mandatory)][string]$ReceiptPath)
. "$PSScriptRoot\Common.ps1"
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json -Depth 100
Assert-CollectionReceipt $receipt
foreach ($id in @($receipt.associationIds) + @($receipt.dcrId)) {
    $resource = Get-CollectionResource $receipt.subscriptionId $id
    Assert-CollectionOwnership $receipt $resource $id
    $recorded = @($receipt.fingerprints | Where-Object id -EQ $id)[0].sha256
    if ((Get-CollectionFingerprint $resource) -cne $recorded) { throw "Owned configuration drift; cleanup held: $id" }
}
foreach ($id in @($receipt.associationIds) + @($receipt.dcrId)) {
    if ($PSCmdlet.ShouldProcess($id,'Delete exact owned collection resource')) {
        $null = Invoke-CollectionAz @('rest','--subscription',$receipt.subscriptionId,'--method','delete','--url',"https://management.azure.com${id}?api-version=2023-03-11")
        try { $null = Get-CollectionResource $receipt.subscriptionId $id }
        catch {
            if ($_.FullyQualifiedErrorId -like 'CollectionResourceNotFound*') { continue }
            throw
        }
        throw "Deletion not yet confirmed by 404; cleanup held: $id"
    }
}
