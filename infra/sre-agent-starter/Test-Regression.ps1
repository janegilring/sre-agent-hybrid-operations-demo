#requires -Version 7.2
[CmdletBinding()]
param([switch]$IncludeMaintainerSdk, [string]$AzureCliPython)
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
    foreach ($call in $mockState.RoleCalls) {
        Assert (($call[0..2] -join ' ') -ceq 'role assignment list') 'Unexpected role command.'
        Assert ('--all' -notin $call) 'Do not combine exact scope with --all.'
        foreach ($option in @('--subscription','--scope','--fill-principal-name','--fill-role-definition-name','--output')) {
            $positions = @(0..($call.Count-1) | Where-Object { $call[$_] -ceq $option })
            Assert ($positions.Count -eq 1 -and $positions[0] -lt $call.Count-1) "Missing/duplicate argument: $option"
        }
        foreach ($option in @('--fill-principal-name','--fill-role-definition-name')) {
            Assert ($call[[array]::IndexOf($call,$option)+1] -ceq 'false') 'No directory/definition expansion.'
        }
        Assert ($call[[array]::IndexOf($call,'--output')+1] -ceq 'json') 'Require JSON output.'
    }
    if ($AzureCliPython -and !$IncludeMaintainerSdk) { throw 'AzureCliPython requires IncludeMaintainerSdk.' }
    if ($IncludeMaintainerSdk) {
        if (!$AzureCliPython) {
            $AzureCliPython = Join-Path (Split-Path (Split-Path (Get-Command az.cmd -CommandType Application).Source)) 'python.exe'
        }
        & $AzureCliPython -I -B "$PSScriptRoot\test_role_cli.py" $callsPath
        Assert ($LASTEXITCODE -eq 0) 'Installed Azure CLI offline validator regression failed.'
    } else {
        Write-Output 'NOT RUN: installed Azure CLI SDK validator/pagination test. Maintainers must also run -IncludeMaintainerSdk; PowerShell mocks are not SDK acceptance.'
    }
    Write-Output "PASS: $subnetCases functional subnet cases; cleanup preview, exact agent/target role discovery, principal refusal, mocked apply and post-delete verification. No Azure calls."
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
    Remove-Item Function:\az
}
