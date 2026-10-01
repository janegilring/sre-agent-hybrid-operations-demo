#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_().-]{1,90}$')][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ParametersFile,
    [Parameter(Mandatory)][string]$ManifestPath,
    [switch]$Apply
)
. "$PSScriptRoot\Common.ps1"
if (!$Apply) { throw 'Deployment is separate from validation: explicitly supply -Apply after reviewing Validate.ps1 output.' }
if (Test-Path -LiteralPath $ManifestPath) { throw 'Manifest already exists; no overwrite/redeploy supported.' }
$values = Read-StarterParameters $ParametersFile
& "$PSScriptRoot\Validate.ps1" -SubscriptionId $SubscriptionId -ResourceGroup $ResourceGroup -ParametersFile $ParametersFile
if (!$PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup/$($values.agentName)",'Create NEW SRE starter resources and explicitly opted-in roles')) { return }
Assert-NewResources $SubscriptionId $ResourceGroup $values
$values.ownershipToken = [guid]::NewGuid().ToString()
$deploymentName = "sre-starter-$($values.ownershipToken)"
$parameters = @{}
foreach ($entry in $values.GetEnumerator()) { $parameters[$entry.Key] = @{value=$entry.Value} }
$manifest = @{
    version=1; subscriptionId="$SubscriptionId"; resourceGroup=$ResourceGroup
    deploymentName=$deploymentName; values=$values
    resourceIds=@(Get-OwnedIds $SubscriptionId $ResourceGroup $values.agentName)
    state='Pending'; outputs=$null
}
$null = New-Item -ItemType File -Path $ManifestPath -Value ($manifest | ConvertTo-Json -Depth 30)
$parameterPath = "$ManifestPath.parameters.local.json"
$templatePath = "$ManifestPath.template.local.json"
if ((Test-Path -LiteralPath $parameterPath) -or (Test-Path -LiteralPath $templatePath)) { throw 'Generated artifact path already exists.' }
$null = New-Item -ItemType File -Path $parameterPath -Value (@{parameters=$parameters} | ConvertTo-Json -Depth 30)
try {
    & bicep build "$PSScriptRoot\main.bicep" --outfile $templatePath
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed before deployment.' }
    $result = Invoke-AzJson @('deployment','group','create','--subscription',"$SubscriptionId",'--resource-group',$ResourceGroup,'--name',$deploymentName,'--mode','Incremental','--template-file',$templatePath,'--parameters',"@$parameterPath")
    $manifest.outputs = $result.properties.outputs
    $manifest.state = $result.properties.provisioningState
    $manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ManifestPath
    if ($manifest.state -ne 'Succeeded') { throw 'Deployment did not succeed; retain manifest for owned-resource cleanup.' }
    Write-Output "Created. Retain $ManifestPath. Private network, OAuth and runtime acceptance remain manual."
} finally {
    foreach ($path in @($parameterPath,$templatePath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
}
