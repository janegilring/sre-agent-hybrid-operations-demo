#Requires -Version 7.5
. "$PSScriptRoot\..\..\..\scripts\TestSupport.ps1"
$root = Split-Path $PSScriptRoot
function Get-Missing($Expected, $Rows, $Now=100, $Freshness=10) {
    $recent=@($Rows | Where-Object { $_[1] -gt ($Now-$Freshness) -and $_[1] -le $Now } | ForEach-Object { $_[0].ToLowerInvariant() })
    @($Expected | ForEach-Object { $_.ToLowerInvariant() } | Where-Object { $_ -notin $recent } | Sort-Object -Unique)
}
function Get-Sustained($Rows, $Threshold, [bool]$High=$true, $Required=3, $MinimumSamples=3) {
    $series=@{}
    foreach ($row in $Rows) {
        $resource,$instance,$bucket,$value=$row
        if ($value -lt 0 -or $value -gt 100) { continue }
        $key=$resource.ToLowerInvariant()+'|'+$instance.ToLowerInvariant()
        if (!$series.ContainsKey($key)) { $series[$key]=@{} }
        if (!$series[$key].ContainsKey($bucket)) { $series[$key][$bucket]=[Collections.Generic.List[double]]::new() }
        $series[$key][$bucket].Add($value)
    }
    foreach ($key in ($series.Keys | Sort-Object)) {
        $buckets=$series[$key]
        if ($buckets.Count -ne $Required -or @($buckets.Values | Where-Object Count -LT $MinimumSamples).Count) { continue }
        $means=@($buckets.Values | ForEach-Object { ($_ | Measure-Object -Average).Average })
        if (($High -and ($means | Measure-Object -Minimum).Minimum -gt $Threshold) -or
            (!$High -and ($means | Measure-Object -Maximum).Maximum -lt $Threshold)) { $key }
    }
}
Assert-Equal @(Get-Missing @('/A','/B') @()) @('/a','/b') 'all absent'
Assert-Equal @(Get-Missing @('/A','/B') @(,@('/a',99))) @('/b') 'never seen'
Assert-Equal @(Get-Missing @('/A','/B','/C') @(@('/a',90),@('/B',101),@('/c',99))) @('/a','/b') 'stale/future/case'
$rows=@(foreach ($b in 0..2) { foreach ($i in 1..3) { ,@('/A','_Total',$b,95) } })
Assert-Equal @(Get-Sustained $rows 90) @('/a|_total') 'sustained CPU'
Assert-Equal @(Get-Sustained $rows[0..7] 90) @() 'insufficient samples'
$low = @(foreach ($i in 1..4) { ,@('/a','_Total',1,0) })
Assert-Equal @(Get-Sustained ($rows + $low) 90) @() 'low bin prevents sustained'
$fraction=@($rows | ForEach-Object { ,@($_[0],$_[1],$_[2],0.95) })
Assert-Equal @(Get-Sustained $fraction 90) @() 'percent not fraction'
$diskRows=@(foreach ($d in @(@('C:',5),@('D:',80))) { foreach ($b in 0..2) { foreach ($i in 1..3) { ,@('/A',$d[0],$b,$d[1]) } } })
Assert-Equal @(Get-Sustained $diskRows 10 $false) @('/a|c:') 'disk instance not host average'
Assert-Equal (100*(1024*1024*1024/1048576)/16384) 6.25 'physical memory conversion'
$bicep=Get-Content "$root\main.bicep" -Raw
foreach ($name in @('inventory','heartbeat','cpu','memory','disk','coverage')) { Assert-That ($bicep.Contains("loadTextContent('queries/$name.kql')")) 'canonical ingestion' }
foreach ($text in @('param enabled bool = true','resolveConfiguration: {','autoResolved: true',"timeToResolve: 'PT`${recoveryMinutes}M'",'param recoveryMinutes int = 10',"resourceIdColumn: '_ResourceId'")) { Assert-That ($bicep.Contains($text)) "Bicep contract $text" }
Assert-That ($bicep -notmatch '\bautoMitigate\s*:' -and !$bicep.Contains('Spooler')) 'exclusive recovery and no service coupling'
$heartbeat=(Get-Content "$root\queries\heartbeat.kql" -Raw).Replace("`r`n","`n")
foreach ($text in @("Inventory`n| join kind=leftouter Recent",'TimeGenerated > ago(Freshness)','TimeGenerated = now()','tolower(_ResourceId)','isnull(LastSeen)')) { Assert-That ($heartbeat.Contains($text)) "heartbeat $text" }
$coverage=(Get-Content "$root\queries\coverage.kql" -Raw).Replace("`r`n","`n")
Assert-That ($coverage.Contains("Expected`n| join kind=leftouter Observed") -and $coverage.Contains('CoveredBins')) 'inventory driven coverage'
foreach ($name in @('cpu','memory','disk')) {
    $text=Get-Content "$root\queries\$name.kql" -Raw
    Assert-That ($text.Contains('TimeGenerated >= WindowStart and TimeGenerated < WindowEnd') -and $text.Contains('Bins == RequiredBins and LeastSamples >= MinSamples')) 'closed bins and sample coverage'
}
Assert-That ((Get-Content "$root\queries\cpu.kql" -Raw).Contains('min(Average)')) 'CPU all bins high'
Assert-That ((Get-Content "$root\queries\disk.kql" -Raw).Contains('max(Average)')) 'disk all bins low'
Assert-That ((Get-Content "$root\queries\memory.kql" -Raw).Contains('1048576.0')) 'bytes conversion'
Assert-That ((Read-TestJson "$root\targets.example.json")[0].resourceId.Contains('00000000-0000-0000-0000-000000000000')) 'synthetic inventory'
'PASS: nine monitoring reference-model and query/template contract groups; not live KQL execution.'
