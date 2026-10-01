#requires -Version 7.2
[CmdletBinding()]
param([string]$AzureCliPython)
. "$PSScriptRoot\Common.ps1"
function Assert([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action,[string]$Pattern) {
    try { & $Action } catch {
        Assert ($_.Exception.Message -match $Pattern) "Unexpected failure: $_"
        return
    }
    throw "Expected rejection: $Pattern"
}

$testSub = '11111111-1111-1111-1111-111111111111'
$subnetId = "/subscriptions/$testSub/resourceGroups/network/providers/Microsoft.Network/virtualNetworks/test/subnets/agent"
$mockState = @{
    SubnetProperties = @{}
    VnetLocation = 'eastus2'
    RoleCalls = [Collections.Generic.List[object]]::new()
    Roles = @()
    Deleted = [Collections.Generic.List[string]]::new()
}
function az {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'resource' -and $args[1] -eq 'show') {
        $id = $args[[array]::IndexOf($args,'--ids') + 1]
        if ($id -eq $subnetId) { return @{properties=$mockState.SubnetProperties} | ConvertTo-Json -Depth 20 }
        return @{location=$mockState.VnetLocation} | ConvertTo-Json
    }
    if ($args[0] -eq 'resource' -and $args[1] -eq 'list') { return '[]' }
    if ($args[0] -eq 'role' -and $args[1] -eq 'assignment') {
        if ($args[2] -eq 'list') {
            $mockState.RoleCalls.Add(@($args))
            $scope = $args[[array]::IndexOf($args,'--scope') + 1]
            # Match the CLI's default exact-scope behavior, not its transport response.
            return ConvertTo-Json -Depth 20 -InputObject @($mockState.Roles | Where-Object scope -EQ $scope)
        }
        if ($args[2] -eq 'delete') {
            $id = $args[[array]::IndexOf($args,'--ids') + 1]
            $mockState.Deleted.Add($id)
            $mockState.Roles = @($mockState.Roles | Where-Object id -NE $id)
            return '{}'
        }
    }
    throw "Unapproved offline operation: $args"
}

$scratch = Join-Path $PSScriptRoot ".local\regression-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory $scratch
try {
    $subnetCases = 0
    foreach ($form in @('addressPrefix','addressPrefixes')) {
        $mockState.SubnetProperties = @{delegations=@(@{properties=@{serviceName='Microsoft.App/environments'}})}
        $mockState.SubnetProperties[$form] = if ($form -eq 'addressPrefix') { '10.0.0.0/27' } else { @('10.0.0.0/27','10.1.0.0/24') }
        $warnings = @(Assert-Subnet $subnetId 'eastus2' $testSub 3>&1)
        Assert ($warnings.Count -eq 1 -and "$warnings" -match 'NOT attached') 'Expected successful subnet preflight output.'
        $subnetCases++
        foreach ($collection in @('ipConfigurations','privateEndpoints')) {
            $mockState.SubnetProperties[$collection] = @(@{id='occupied'})
            Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'Subnet is in use'
            $mockState.SubnetProperties.Remove($collection)
            $subnetCases++
        }
        $mockState.VnetLocation = 'westus2'
        Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'same-region'
        $mockState.VnetLocation = 'eastus2'
        $subnetCases++
        foreach ($delegation in @(@(), @(@{properties=@{serviceName='wrong/service'}}), @(@{properties=@{}}))) {
            $mockState.SubnetProperties['delegations'] = $delegation
            Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'Missing Microsoft.App/environments'
            $subnetCases++
        }
        $mockState.SubnetProperties.Remove('delegations')
        Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'Missing Microsoft.App/environments'
        $subnetCases++
        $mockState.SubnetProperties['delegations'] = @(@{properties=@{serviceName='Microsoft.App/environments'}})
        foreach ($prefix in @('10.0.0.0/28','10.0.0.0/33','999.0.0.0/27','10.0.0/27','::/64','10.0.0.0/-1','garbage','')) {
            $mockState.SubnetProperties[$form] = if ($form -eq 'addressPrefix') { $prefix } else { @($prefix) }
            Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'same-region IPv4 /27'
            $subnetCases++
        }
    }
    $mockState.SubnetProperties = @{delegations=@(@{properties=@{serviceName='Microsoft.App/environments'}})}
    Assert-Throws { Assert-Subnet $subnetId 'eastus2' $testSub } 'same-region IPv4 /27'
    Assert-Throws { Assert-Subnet ($subnetId.Replace($testSub,[guid]::Empty.ToString())) 'eastus2' $testSub } 'exact resource ID'
    $subnetCases += 2

    $ids = @(Get-OwnedIds $testSub 'rg-agent' 'test-agent')
    $targetScope = "/subscriptions/$testSub/resourceGroups/rg-workload"
    $principal = '22222222-2222-2222-2222-222222222222'
    $user = '33333333-3333-3333-3333-333333333333'
    $token = [guid]::NewGuid().ToString()
    $receipt = @{
        version=1; subscriptionId=$testSub; resourceGroup='rg-agent'; resourceIds=$ids
        values=@{agentName='test-agent'; ownershipToken=$token; targetResourceGroupNames=@('rg-workload'); grantTargetReader=$true; agentAccessUserObjectIds=@($user)}
        outputs=@{userAssignedPrincipalId=@{value=$principal}}
    }
    $manifestPath = Join-Path $scratch 'manifest.json'
    $receipt | ConvertTo-Json -Depth 20 | Set-Content $manifestPath
    function New-TestRole($Scope,$PrincipalId,$Definition) {
        @{id="$Scope/providers/Microsoft.Authorization/roleAssignments/$([guid]::NewGuid())"; scope=$Scope; principalId=$PrincipalId
          roleDefinitionId="/providers/Microsoft.Authorization/roleDefinitions/$Definition"; description="sre-agent-starter:$token"}
    }
    $reader = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
    $targetRole = New-TestRole $targetScope $principal $reader
    $userRole = New-TestRole $ids[0] $user 'e79298df-d852-4c6d-84f9-5d13249d1e55'
    $inherited = New-TestRole "/subscriptions/$testSub" $principal $reader
    $other = New-TestRole "/subscriptions/$testSub/resourceGroups/elsewhere" $principal $reader
    $mockState.Roles = @($targetRole,$userRole,$inherited,$other)
    $preview = & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-agent' -ManifestPath $manifestPath
    Assert (("$preview").Contains($targetRole.id) -and ("$preview").Contains($userRole.id)) 'Preview lost target or agent resource role.'
    Assert (!(("$preview").Contains($inherited.id)) -and !(("$preview").Contains($other.id))) 'Cross-scope false positive.'
    Assert ($mockState.Deleted.Count -eq 0) 'Preview deleted a role.'
    $targetRole.principalId = $user
    Assert-Throws { & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-agent' -ManifestPath $manifestPath } 'Foreign role scope/principal'
    $targetRole.principalId = $principal
    & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-agent' -ManifestPath $manifestPath -Apply -Confirm:$false | Out-Null
    Assert ($mockState.Deleted.Count -eq 2 -and $targetRole.id -in $mockState.Deleted -and $userRole.id -in $mockState.Deleted) 'Incorrect role deletion set.'
    Assert ($mockState.Roles.Count -eq 2) 'Unrelated roles were deleted.'
    Assert ((Get-Content $manifestPath -Raw | ConvertFrom-Json).state -eq 'Cleaned') 'Cleanup did not complete verification.'
    $callsPath = Join-Path $scratch 'cli-calls.json'
    ConvertTo-Json -Depth 20 -InputObject @($mockState.RoleCalls.ToArray()) | Set-Content $callsPath
    if (!$AzureCliPython) {
        $AzureCliPython = Join-Path (Split-Path (Split-Path (Get-Command az.cmd -CommandType Application).Source)) 'python.exe'
    }
    & $AzureCliPython -I -B "$PSScriptRoot\test_role_cli.py" $callsPath
    Assert ($LASTEXITCODE -eq 0) 'Installed Azure CLI offline validator regression failed.'
    Write-Output "PASS: $subnetCases functional subnet cases; cleanup preview, exact agent/target role discovery, principal refusal, mocked apply and post-delete verification. No Azure calls."
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
    Remove-Item Function:\az
}
