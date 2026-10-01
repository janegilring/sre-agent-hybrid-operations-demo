#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][guid]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ManifestPath,
    [switch]$Apply
)
. "$PSScriptRoot\Common.ps1"
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -AsHashtable
if ($manifest.version -ne 1 -or $manifest.subscriptionId -ne "$SubscriptionId" -or $manifest.resourceGroup -ne $ResourceGroup) {
    throw 'Manifest does not match the explicitly selected subscription/RG.'
}
if ($ResourceGroup -notmatch '^[A-Za-z0-9_().-]{1,90}$' -or $manifest.values.agentName -notmatch '^[A-Za-z][-A-Za-z0-9]{0,30}[A-Za-z0-9]$') { throw 'Invalid manifest resource names.' }
foreach ($rg in $manifest.values.targetResourceGroupNames) {
    if ($rg -notmatch '^[A-Za-z0-9_().-]{1,90}$' -or $rg.EndsWith('.')) { throw 'Invalid manifest target scope.' }
}
$token = [guid]::Parse($manifest.values.ownershipToken).ToString()
if ($token -eq [guid]::Empty.ToString()) { throw 'Invalid ownership token.' }
$expected = @(Get-OwnedIds $SubscriptionId $ResourceGroup $manifest.values.agentName)
if (@(Compare-Object $expected @($manifest.resourceIds)).Count) { throw 'Foreign resource IDs in manifest.' }
$existing = @(Invoke-AzJson @('resource','list','--subscription',"$SubscriptionId",'--resource-group',$ResourceGroup))
$owned = @($existing | Where-Object id -In $expected)
foreach ($resource in $owned) {
    if (!$resource.tags -or $resource.tags.ownershipToken -ne $token -or $resource.tags.component -ne 'sre-agent-starter') {
        throw "Ownership mismatch; refusing all cleanup: $($resource.id)"
    }
}
$principalId = $null
if ($expected[3] -in @($owned | ForEach-Object id)) {
    $identity = Invoke-AzJson @('resource','show','--ids',$expected[3],'--api-version','2024-11-30','--subscription',"$SubscriptionId")
    $principalId = $identity.properties.principalId
} elseif ($manifest.outputs -and $manifest.outputs.userAssignedPrincipalId) {
    $principalId = $manifest.outputs.userAssignedPrincipalId.value
}
$targetScopes = @($manifest.values.targetResourceGroupNames | ForEach-Object { "/subscriptions/$SubscriptionId/resourceGroups/$_" })
# Scoped CLI listing excludes children; enumerate the agent's user grants explicitly.
$scopes = @($targetScopes + "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" + $expected[0] | Sort-Object -Unique)
$roles = @()
foreach ($scope in $scopes) {
    $listed = @(Invoke-AzJson @('role','assignment','list','--subscription',"$SubscriptionId",'--scope',$scope,'--fill-principal-name','false','--fill-role-definition-name','false'))
    foreach ($role in $listed) {
        if ($role.description -ne "sre-agent-starter:$token") { continue }
        $definition = $role.roleDefinitionId.Split('/')[-1]
        $isTargetReader = $manifest.values.grantTargetReader -and $role.scope -in $targetScopes -and $definition -eq 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -and $principalId -and $role.principalId -eq $principalId
        $isUserAccess = $role.scope -eq $expected[0] -and $role.principalId -in $manifest.values.agentAccessUserObjectIds -and $definition -in @('acdd72a7-3385-48ef-bd42-f606fba81ae7','e79298df-d852-4c6d-84f9-5d13249d1e55')
        if (!$isTargetReader -and !$isUserAccess) { throw "Foreign role scope/principal in owned set: $($role.id)" }
        if ($role.id -notmatch "^$([regex]::Escape($role.scope))/providers/Microsoft.Authorization/roleAssignments/[0-9a-f-]{36}$") { throw 'Invalid role assignment ID.' }
        $roles += $role
    }
}
$roles = @($roles | Sort-Object id -Unique)
Write-Output "Exact owned roles: $(@($roles | ForEach-Object id) -join ', ')"
Write-Output "Exact owned resources: $(@($owned | ForEach-Object id) -join ', ')"
if (!$Apply) { Write-Output 'Preview only; use -Apply to request deletion.'; return }
if (!$PSCmdlet.ShouldProcess("$SubscriptionId/$ResourceGroup",'Delete only verified owned roles and starter resources; never resource groups or workload resources')) { return }
foreach ($role in $roles) {
    $null = Invoke-AzJson @('role','assignment','delete','--ids',$role.id,'--subscription',"$SubscriptionId")
}
$remainingRoles = @()
foreach ($scope in $scopes) {
    $remainingRoles += @(Invoke-AzJson @('role','assignment','list','--subscription',"$SubscriptionId",'--scope',$scope,'--fill-principal-name','false','--fill-role-definition-name','false'))
}
if (@($remainingRoles | Where-Object { $_.id -in @($roles | ForEach-Object id) }).Count) { throw 'Role cleanup not yet verified; retain manifest and retry after propagation.' }
foreach ($id in $expected) {
    if ($id -in @($owned | ForEach-Object id)) {
        $null = Invoke-AzJson @('resource','delete','--ids',$id,'--subscription',"$SubscriptionId")
    }
}
$remaining = @(Invoke-AzJson @('resource','list','--subscription',"$SubscriptionId",'--resource-group',$ResourceGroup))
if (@($remaining | Where-Object id -In $expected).Count) { throw 'Cleanup incomplete; preserve manifest and retry after reviewing resource state.' }
$manifest.state = 'Cleaned'
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ManifestPath
Write-Output 'Owned resources removed; deployment history retained. No resource group was deleted.'
