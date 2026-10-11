#Requires -Version 7.5
. "$PSScriptRoot\..\..\..\scripts\TestSupport.ps1"
$root=Split-Path $PSScriptRoot
$query=Get-Content "$root\stopped-transition.kql" -Raw
$template=Get-Content "$root\main.bicep" -Raw
$target='/subscriptions/00000000-0000-4000-8000-000000000000/resourceGroups/rg-demo/providers/Microsoft.HybridCompute/machines/demo-windows-01'
$stop='The Print Spooler service entered the stopped state.'
$run='The Print Spooler service entered the running state.'
function New-Event($Changes=@{}) {
    $row=@{
        _ResourceId=$target; EventLog='System'; Source='Service Control Manager'; EventID=7036
        RenderedDescription=$stop
        EventData='<DataItem><EventData><Data Name="param1">Print Spooler</Data><Data Name="param2">stopped</Data></EventData></DataItem>'
        source_age_seconds=60; ingestion_age_seconds=30
    }
    foreach ($key in $Changes.Keys) { $row[$key]=$Changes[$key] }
    return $row
}
function Get-Observed($Rows) {
    foreach ($r in $Rows) {
        if ($r._ResourceId -ieq $target -and $r.EventLog -ceq 'System' -and $r.Source -ceq 'Service Control Manager' -and
            $r.EventID -eq 7036 -and $null -ne $r.RenderedDescription -and $r.RenderedDescription.Trim() -ceq $stop -and
            $null -ne $r.source_age_seconds -and $r.source_age_seconds -ge 0 -and $r.source_age_seconds -le 600 -and
            $null -ne $r.ingestion_age_seconds -and $r.ingestion_age_seconds -ge 0 -and $r.ingestion_age_seconds -le 300) { $r }
    }
}
foreach ($fragment in @(
    'dynamic(__TARGET_RESOURCE_IDS__)','_ResourceId in~ (TargetIds)','TimeGenerated >= ago(10m) and TimeGenerated <= now()',
    'EventLog == "System" and Source == "Service Control Manager" and EventID == 7036',
    'EventIngestedUtc = ingestion_time()','isnotnull(EventIngestedUtc)','EventIngestedUtc >= ago(5m) and EventIngestedUtc <= now()',
    ('trim(@"\s+", RenderedDescription) == "'+$stop+'"'),'CurrentState = "Unknown"','Evidence = "StoppedTransitionObserved"'
)) { Assert-That ($query.Contains($fragment)) "query $fragment" }
Assert-That (!$query.Contains('summarize') -and !$query.Contains('arg_max')) 'no empty aggregation/current state oracle'
foreach ($fragment in @(
    "'Microsoft-Event'",'EventID=7036','param1','Print Spooler','scope: machine','autoMitigate: false',
    'skipQueryValidation: false','threshold: 0',"timeAggregation: 'Count'",'param deployAlert bool = false',
    'if (deployAlert)','enabled: true',"loadTextContent('stopped-transition.kql')",'string([machine.id])'
)) { Assert-That ($template.Contains($fragment)) "template $fragment" }
foreach ($forbidden in @('roleAssignments','virtualMachines/extensions','7031','7034')) { Assert-That (!$template.Contains($forbidden)) "forbidden $forbidden" }
$compiled=Get-CompiledTemplate "$root\main.bicep"
$resources=if ($compiled.resources -is [Collections.IDictionary]) { @($compiled.resources.Values) } else { @($compiled.resources) }
$existing=@($resources | Where-Object { $_['existing'] })
Assert-Equal @($existing | ForEach-Object { $_.type }) @('Microsoft.HybridCompute/machines') 'existing machine only'
$resources=@($resources | Where-Object { !$_['existing'] })
Assert-Equal $resources.Count 3 'three resources'
$dcr=$resources | Where-Object { $_.type.EndsWith('/dataCollectionRules') }
$assoc=$resources | Where-Object { $_.type.EndsWith('/dataCollectionRuleAssociations') }
$alert=$resources | Where-Object { $_.type.EndsWith('/scheduledQueryRules') }
Assert-Equal $dcr.properties.dataFlows[0].streams @('Microsoft-Event') 'event stream'
Assert-That ($assoc.scope -match 'machine') 'association scope'
Assert-Equal $alert.condition "[parameters('deployAlert')]" 'opt in alert'
Assert-Equal $alert.properties.autoMitigate $false 'no automatic recovery'
Assert-Equal $alert.properties.criteria.allOf[0].timeAggregation 'Count' 'count events'
Assert-Equal $compiled.parameters.deployAlert.defaultValue $false 'default no alert'
Assert-Equal @(Get-Observed @((New-Event @{RenderedDescription="$stop`r`n"}))).Count 1 'outer whitespace'
Assert-Equal @(Get-Observed @((New-Event @{RenderedDescription=$run}))).Count 0 'running not stop'
$historical=New-Event @{source_age_seconds=120}
Assert-Equal @(Get-Observed @($historical,(New-Event @{RenderedDescription=$run}))) @($historical) 'stop then start remains historical'
foreach ($text in @('Der Dienst Druckwarteschlange wurde beendet.','Spooler stopped',$stop.Replace('Print Spooler','Other Print Spooler'),($stop+$run),'')) {
    Assert-Equal @(Get-Observed @((New-Event @{RenderedDescription=$text}))).Count 0 'localized/renamed/partial/ambiguous'
}
foreach ($change in @(@{_ResourceId="$target-other"},@{EventLog='Application'},@{Source='Other'},@{EventID=7031})) {
    Assert-Equal @(Get-Observed @((New-Event $change))).Count 0 'cross target/provider/log/id'
}
Assert-Equal @(Get-Observed @((New-Event @{_ResourceId=$target.ToUpperInvariant()}))).Count 1 'case insensitive target'
foreach ($change in @(@{source_age_seconds=601;ingestion_age_seconds=0},@{source_age_seconds=-1},@{ingestion_age_seconds=301},@{ingestion_age_seconds=-1},@{ingestion_age_seconds=$null})) {
    Assert-Equal @(Get-Observed @((New-Event $change))).Count 0 'source and ingestion bounds independent'
}
Assert-Equal @(Get-Observed @((New-Event @{source_age_seconds=600;ingestion_age_seconds=300}))).Count 1 'inclusive time bounds'
Assert-Equal @(Get-Observed @()).Count 0 'no data not healthy'
Assert-Equal @(Get-Observed @((New-Event @{source_age_seconds=3600}))).Count 0 'stop before collection'
foreach ($change in @(@{_ResourceId=$null},@{RenderedDescription=$null},@{source_age_seconds=$null})) {
    Assert-Equal @(Get-Observed @((New-Event $change))).Count 0 'missing evidence'
}
'PASS: eleven service-event query/template/reference-model groups, including compiled Bicep; no live capture.'
