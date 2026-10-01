#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_().-]{1,90}$')][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ParametersFile,
    [string]$ExistingSubnetResourceId,
    [switch]$LocalOnly
)
. "$PSScriptRoot\Common.ps1"
$values = Read-StarterParameters $ParametersFile
$compiled = & bicep build "$PSScriptRoot\main.bicep" --stdout
if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }
if ($LocalOnly) { Write-Output 'Local compilation and parameter checks passed; ARM/region/service validation NOT performed.'; return }
Assert-NewResources $SubscriptionId $ResourceGroup $values
Assert-Subnet $ExistingSubnetResourceId $values.location $SubscriptionId
$provider = Invoke-AzJson @('provider','show','--namespace','Microsoft.App','--subscription',"$SubscriptionId")
$type = @($provider.resourceTypes | Where-Object resourceType -eq 'agents')
if ($provider.registrationState -ne 'Registered' -or !$type.Count -or '2026-01-01' -notin $type[0].apiVersions) { throw 'Microsoft.App/agents API unavailable or provider unregistered; request administrator review.' }
if ($values.location -notin @($type[0].locations | ForEach-Object { ($_ -replace '\s','').ToLowerInvariant() })) { throw 'Selected region is not advertised for Microsoft.App/agents in this subscription.' }
Write-Output "Published agent locations: $($type[0].locations -join ', '). Confirm subscription offer/region support."
$null = New-Item -ItemType Directory "$PSScriptRoot\.local" -Force
$buildPath = "$PSScriptRoot\.local\validate-$([guid]::NewGuid()).json"
$parameterPath = "$buildPath.parameters.local.json"
try {
    $null = New-Item -ItemType File -Path $buildPath -Value ($compiled -join "`n")
    $parameters = @{}
    foreach ($entry in $values.GetEnumerator()) { $parameters[$entry.Key] = @{value=$entry.Value} }
    $null = New-Item -ItemType File -Path $parameterPath -Value (@{parameters=$parameters} | ConvertTo-Json -Depth 30)
    $argsBase = @('--subscription',"$SubscriptionId",'--resource-group',$ResourceGroup,'--template-file',$buildPath,'--parameters',"@$parameterPath")
    $null = Invoke-AzJson (@('deployment','group','validate') + $argsBase)
    & az deployment group what-if @argsBase --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'ARM what-if failed.' }
} finally {
    foreach ($path in @($buildPath,$parameterPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
}
Write-Warning 'Read-only validation does not certify provisioning, effective permissions, network reachability, OAuth or runtime acceptance.'
