#Requires -Version 7.5
. "$PSScriptRoot\..\..\scripts\TestSupport.ps1"
. "$PSScriptRoot\Test-Inputs.ps1"
$sub = '00000000-0000-0000-0000-000000000000'
$machine = "/subscriptions/$sub/resourceGroups/example-arc/providers/Microsoft.HybridCompute/machines/example-server"
$owner = '11111111-1111-4111-8111-111111111111'
function New-Parameters {
    @{parameters=@{ownershipId=@{value=$owner}; machineResourceIds=@{value=@($machine)}; actionGroupResourceIds=@{value=@()}}}
}
Assert-Equal @(Test-ArcParameters (New-Parameters) $sub) @((Get-ArcAlertName $owner $machine)) 'valid no actions'
$ids = @($machine, ($machine+'2'), $machine.Replace('example-arc','other-group'))
$names = @($ids | ForEach-Object { Get-ArcAlertName $owner $_ })
Assert-Equal $names[0].Substring('arc-connectivity-single-'.Length).Replace('-','') '30f797b84b6c562187452d2b2807230a' 'prior UUIDv5 implementation parity vector'
Assert-Equal @($names | Sort-Object -Unique).Count 3 'unique targets'
Assert-Equal $names[0] (Get-ArcAlertName $owner.ToUpperInvariant() $machine.ToUpperInvariant()) 'case insensitive names'
Assert-Equal @(2..0 | ForEach-Object { Get-ArcAlertName $owner $ids[$_] }) @($names[2],$names[1],$names[0]) 'order independent names'
Assert-That ($names[0] -ne (Get-ArcAlertName '22222222-2222-4222-8222-222222222222' $machine)) 'owner bound name'
$p = New-Parameters; $p.parameters.Remove('actionGroupResourceIds'); $null = Test-ArcParameters $p $sub
$p.parameters.actionGroupResourceIds = @{value=@("/subscriptions/$sub/resourceGroups/example-arc/providers/Microsoft.Insights/actionGroups/example")}
$null = Test-ArcParameters $p $sub
foreach ($bad in @('', ' ', "$machine/", "$machine/extensions/agent", ($machine -replace '[^/]+$',''), "$machine*", $machine.Replace('example-server','bad name'), $machine.Replace('Microsoft.HybridCompute','Microsoft.Compute'), "/subscriptions/$sub", $machine.Replace($sub,$owner))) {
    $p=New-Parameters; $p.parameters.machineResourceIds.value=@($bad)
    Assert-Rejected { Test-ArcParameters $p $sub } 'requires exact|selected subscription'
}
foreach ($bad in @(@(), $null, $machine, @($null), @($machine,$machine.ToUpperInvariant()))) {
    $p=New-Parameters; $p.parameters.machineResourceIds.value=$bad
    Assert-Rejected { Test-ArcParameters $p $sub } 'array|requires exact|duplicate'
}
foreach ($bad in @('', (' '*36), $sub, '[newGuid()]', ('z'*36))) {
    $p=New-Parameters; $p.parameters.ownershipId.value=$bad
    Assert-Rejected { Test-ArcParameters $p $sub } 'UUID'
}
$p=New-Parameters; $p.parameters.actionGroupResourceIds.value=@($machine)
Assert-Rejected { Test-ArcParameters $p $sub } 'requires exact'
foreach ($entry in @(@{value=$owner;reference=@{}}, @{reference=@{}})) {
    $p=New-Parameters; $p.parameters.ownershipId=$entry
    Assert-Rejected { Test-ArcParameters $p $sub } 'literal'
}
$p=New-Parameters; $p.parameters.location=@{value='other'}
Assert-Rejected { Test-ArcParameters $p $sub } 'Unexpected parameters'
foreach ($bad in @($null, 1, 'not-a-subscription')) { Assert-Rejected { Test-ArcParameters (New-Parameters) $bad } 'subscription UUID' }

$template = Get-CompiledTemplate "$PSScriptRoot\main.bicep"
$resources = @(if ($template.resources -is [Collections.IDictionary]) { $template.resources.Values } else { $template.resources })
Assert-Equal $resources.Count 1 'only alert resources'
$rule=$resources[0]
Assert-Equal $rule.type 'Microsoft.Insights/activityLogAlerts' 'resource type'
Assert-Equal $rule.apiVersion '2020-10-01' 'API version'
Assert-Equal $rule.location 'global' 'global alerts'
Assert-Equal $rule.properties.enabled $true 'enabled'
Assert-That (!$rule.Contains('identity')) 'no identity'
Assert-Equal $rule.copy @{name='connectivityAlerts';count="[length(parameters('machineResourceIds'))]"} 'one per machine'
Assert-Equal $rule.name "[format('arc-connectivity-single-{0}', guid(toLower(parameters('ownershipId')), toLower(parameters('machineResourceIds')[copyIndex()])))]" 'owned name'
Assert-Equal $rule.tags['arc-connectivity-owner'] "[parameters('ownershipId')]" 'owner tag'
$expression = "[parameters('machineResourceIds')[copyIndex()]]"
Assert-Equal $rule.properties.scopes @($expression) 'exact scope'
$conditions = $rule.properties.condition.allOf
Assert-Equal $conditions.Count 5 'condition count'
Assert-Equal $conditions[4] @{field='resourceId';equals=$expression} 'flat equality'
foreach ($condition in $conditions) {
    Assert-Equal @($condition.Keys | Sort-Object) @('equals','field') 'no prefix/nested condition'
    Assert-That (!$condition.equals.Contains('*')) 'no wildcard'
}
$expected = @{
    category='ResourceHealth'; resourceType='Microsoft.HybridCompute/machines'
    'properties.previousHealthStatus'='Available'; 'properties.currentHealthStatus'='Unavailable'
}
foreach ($condition in $conditions[0..3]) { Assert-Equal $condition.equals $expected[$condition.field] 'transition fields' }
function Test-Event($Event, $Conditions) {
    foreach ($c in $Conditions) { if ($Event[$c.field] -ine $c.equals) { return $false } }
    return $true
}
$four = @('AzLHOST1','AzLHOST2','app01','db01' | ForEach-Object { $machine -replace '[^/]+$',$_ })
foreach ($target in $four + @(($machine -replace '[^/]+$','foo'))) {
    $expanded = Copy-JsonValue $conditions
    $expanded[4].equals=$target
    $event=@{}; foreach ($c in $expanded) { $event[$c.field]=$c.equals }
    $event.resourceId=$target.ToUpperInvariant()
    Assert-That (Test-Event $event $expanded) 'exact case-insensitive match'
    foreach ($other in @($four | Where-Object { $_ -ne $target }) + @("${target}2","$target-same-prefix","$target/extensions/agent",$target.Replace('example-arc','other-group'),$target.Replace($sub,$owner))) {
        $event.resourceId=$other
        Assert-That (!(Test-Event $event $expanded)) 'reject other machine/prefix/descendant/scope'
    }
}
Assert-Equal $template.parameters.actionGroupResourceIds.defaultValue @() 'no default actions'
$actions=$rule.properties.actions.copy[0]
Assert-Equal $actions.name 'actionGroups' 'action copy'
Assert-Equal $actions.count "[length(parameters('actionGroupResourceIds'))]" 'action count'
Assert-That ((ConvertTo-Json $rule.properties -Depth 30) -notmatch 'query') 'no query'
Assert-That (Test-Event $expected $conditions[0..3]) 'positive transition'
foreach ($pair in @(@('Unavailable','Unavailable'),@('Unknown','Unavailable'),@('Unavailable','Available'),@('',''))) {
    $event=Copy-JsonValue $expected
    $event['properties.previousHealthStatus']=$pair[0]; $event['properties.currentHealthStatus']=$pair[1]
    Assert-That (!(Test-Event $event $conditions[0..3])) 'transition not inventory/recovery'
}
foreach ($cause in @('UserInitiated','PlatformInitiated','Unknown')) {
    $event=Copy-JsonValue $expected; $event['properties.cause']=$cause
    Assert-That (Test-Event $event $conditions[0..3]) 'no cause filter'
}
'PASS: Arc input rejections, deterministic UUIDv5 names, compiled one-per-machine scope/equality and transition contracts.'
