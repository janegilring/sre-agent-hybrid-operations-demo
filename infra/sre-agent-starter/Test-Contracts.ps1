#requires -Version 7.2
[CmdletBinding()]
param()
. "$PSScriptRoot\Common.ps1"
function Assert([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
$json = & bicep build "$PSScriptRoot\main.bicep" --stdout
Assert ($LASTEXITCODE -eq 0) 'Bicep build failed.'
$template = ($json -join "`n") | ConvertFrom-Json -AsHashtable -Depth 100
$resources = if ($template.resources -is [System.Collections.IDictionary]) { @($template.resources.Values) } else { @($template.resources) }
$agent = @($resources | Where-Object { $_.type -eq 'Microsoft.App/agents' })[0]
Assert ($agent.apiVersion -eq '2026-01-01') 'Unexpected agent API.'
Assert ($agent.properties.actionConfiguration.mode -eq 'ReadOnly') 'ReadOnly required.'
Assert ($agent.properties.actionConfiguration.accessLevel -eq 'Low') 'Low required.'
Assert ($agent.identity.type -eq 'SystemAssigned,UserAssigned') 'Both documented identities required.'
Assert (!$template.parameters.grantTargetReader.defaultValue) 'Reader grants must opt in.'
Assert ($template.parameters.agentAccessUserObjectIds.defaultValue.Count -eq 0) 'No implicit user grants.'
Assert (!$agent.properties.ContainsKey('vnetConfiguration')) 'Do not invent VNet properties in current API.'
$text = $json -join "`n"
Assert ($text -notmatch 'b24988ac-6180-42a0-ab88-20f7382dd24c|749f88d5-cbae-40b8-bcfc-e573ddc772fa|8e3af657-a8ff-443c-a75c-2fe8c4bcb635') 'Broad roles prohibited.'
$p = Read-StarterParameters "$PSScriptRoot\parameters.example.json"
$bp = Read-StarterParameters "$PSScriptRoot\main.example.bicepparam"
Assert ($bp.agentName -eq $p.agentName) 'Parameter formats differ.'
Assert ((Get-OwnedIds '00000000-0000-0000-0000-000000000000' 'rg-example' $p.agentName).Count -eq 4) 'Unexpected owned resource set.'
foreach ($path in (Get-ChildItem "$PSScriptRoot\*.ps1")) {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
    Assert (!$errors.Count) "PowerShell parse errors: $($path.Name): $errors"
}
function Assert-Throws([scriptblock]$Action,[string]$Pattern) {
    try { & $Action } catch {
        Assert ($_.Exception.Message -match $Pattern) "Unexpected failure: $_"
        return
    }
    throw "Expected rejection: $Pattern"
}
$scratch = Join-Path $PSScriptRoot ".local\contract-$([guid]::NewGuid()).json"
$null = New-Item -ItemType Directory (Split-Path $scratch) -Force
try {
    $example = Get-Content -Raw "$PSScriptRoot\parameters.example.json" | ConvertFrom-Json -AsHashtable
    $example.parameters.agentAccessUserObjectIds.value = @('')
    $example | ConvertTo-Json -Depth 20 | Set-Content $scratch
    Assert-Throws { Read-StarterParameters $scratch } 'nonempty GUIDs'
    $example.parameters.agentAccessUserObjectIds.value = @()
    $example.parameters.targetResourceGroupNames.value = @('rg-example','rg-example')
    $example | ConvertTo-Json -Depth 20 | Set-Content $scratch
    Assert-Throws { Read-StarterParameters $scratch } 'Duplicate'
    $example.parameters.targetResourceGroupNames.value = @('/subscriptions/foreign')
    $example | ConvertTo-Json -Depth 20 | Set-Content $scratch
    Assert-Throws { Read-StarterParameters $scratch } 'Invalid target'
    $example.parameters.targetResourceGroupNames.value = @('rg-example')
    $example.parameters.grantTargetReader.value = 'false'
    $example | ConvertTo-Json -Depth 20 | Set-Content $scratch
    Assert-Throws { Read-StarterParameters $scratch } 'Boolean'

    # Substitute Azure CLI in this process; no Azure authentication or requests.
    $global:StarterMockCalls = [Collections.Generic.List[string]]::new()
    $global:StarterMockResources = @()
    $global:StarterMockRoles = @()
    function az {
        $global:StarterMockCalls.Add(($args -join ' '))
        $global:LASTEXITCODE = 0
        if ($args[0] -eq 'resource' -and $args[1] -eq 'list') { return ConvertTo-Json -InputObject $global:StarterMockResources -Depth 20 }
        if ($args[0] -eq 'role' -and $args[1] -eq 'assignment' -and $args[2] -eq 'list') { return ConvertTo-Json -InputObject $global:StarterMockRoles -Depth 20 }
        if ($args[0] -eq 'group' -and $args[1] -eq 'show') { return '{}' }
        if ($args[0] -eq 'provider' -and $args[1] -eq 'show') {
            return '{"registrationState":"Registered","resourceTypes":[{"resourceType":"agents","apiVersions":["2026-01-01"],"locations":["East US 2"]}]}'
        }
        if ($args[0] -eq 'deployment' -and $args[1] -eq 'group' -and $args[2] -in @('validate','what-if')) {
            $templateIndex = [array]::IndexOf($args,'--template-file')
            $parametersIndex = [array]::IndexOf($args,'--parameters')
            if ($templateIndex -lt 0 -or !$args[$templateIndex+1].EndsWith('.json')) { throw 'Expected compiled ARM JSON.' }
            if (!(Test-Path -LiteralPath $args[$templateIndex+1])) { throw 'Missing compiled template.' }
            if ($parametersIndex -lt 0 -or !$args[$parametersIndex+1].StartsWith('@')) { throw 'Expected normalized JSON parameters.' }
            return '{}'
        }
        throw "Unapproved mock operation: $args"
    }
    Assert-NewResources '00000000-0000-0000-0000-000000000000' 'rg-example' $p
    $testSub = '00000000-0000-0000-0000-000000000000'
    & "$PSScriptRoot\Validate.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ParametersFile "$PSScriptRoot\main.example.bicepparam" -WarningAction SilentlyContinue | Out-Null
    $receipt = @{
        version=1; subscriptionId=$testSub; resourceGroup='rg-example'
        values=@{agentName=$p.agentName; ownershipToken=[guid]::NewGuid().ToString(); targetResourceGroupNames=@('rg-workload'); grantTargetReader=$false; agentAccessUserObjectIds=@()}
        outputs=$null; resourceIds=@(Get-OwnedIds $testSub 'rg-example' $p.agentName)
    }
    $receipt | ConvertTo-Json -Depth 20 | Set-Content $scratch
    & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ManifestPath $scratch | Out-Null
    $global:StarterMockResources = @(@{id=$receipt.resourceIds[0];tags=@{component='sre-agent-starter';ownershipToken='foreign'}})
    Assert-Throws { Assert-NewResources $testSub 'rg-example' $p } 'overwrite existing'
    Assert-Throws { & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ManifestPath $scratch } 'Ownership mismatch'
    $global:StarterMockResources = @()
    $global:StarterMockRoles = @(@{
        id="$($receipt.resourceIds[0])/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000000"
        description="sre-agent-starter:$($receipt.values.ownershipToken)"
        roleDefinitionId='/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
        principalId='00000000-0000-0000-0000-000000000000'
        scope="/subscriptions/$testSub"
    })
    Assert-Throws { & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ManifestPath $scratch } 'Foreign role scope'
    $global:StarterMockRoles = @()
    Assert-Throws { & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-foreign' -ManifestPath $scratch } 'does not match'
    $receipt.resourceIds += '/subscriptions/foreign/resourceGroups/foreign'
    $receipt | ConvertTo-Json -Depth 20 | Set-Content $scratch
    Assert-Throws { & "$PSScriptRoot\Cleanup.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ManifestPath $scratch } 'Foreign resource IDs'
    Assert-Throws { & "$PSScriptRoot\Deploy.ps1" -SubscriptionId $testSub -ResourceGroup 'rg-example' -ParametersFile "$PSScriptRoot\parameters.example.json" -ManifestPath $scratch } 'explicitly supply -Apply'
    Assert (@($global:StarterMockCalls | Where-Object { $_ -match '\b(create|delete|set)\b' }).Count -eq 0) 'Tests attempted mutation.'
} finally {
    if (Test-Path $scratch) { Remove-Item $scratch }
    if (Test-Path Function:\az) { Remove-Item Function:\az }
    Remove-Variable StarterMockCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable StarterMockResources,StarterMockRoles -Scope Global -ErrorAction SilentlyContinue
}
Write-Output 'PASS: compile, both parameter formats, resource/API/identity/read-only/role contracts, syntax, invalid inputs, empty-state preflight, overwrite refusal, cleanup ownership/scope/ID/role refusal, explicit apply gate. Azure CLI mocked; no Azure calls.'
