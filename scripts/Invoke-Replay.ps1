#Requires -Version 7.5
[CmdletBinding()]
param([string]$Scenario = 'all')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Read-StrictJson.ps1"

function Assert-Replay($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function ConvertTo-ReplayUtc($Value) {
    Assert-Replay ($Value -is [string] -and $Value -cmatch '(Z|\+00:00)\z') 'timestamp must include UTC offset'
    $parsed = [DateTimeOffset]::MinValue
    Assert-Replay ([DateTimeOffset]::TryParse($Value, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) 'invalid timestamp'
    Assert-Replay ($parsed.Offset -eq [timespan]::Zero) 'timestamp must include UTC offset'
    return $parsed
}
function Test-ReplayInteger($Value, [long]$Minimum) {
    return (($Value -is [long] -or $Value -is [int] -or $Value -is [bigint]) -and $Value -ge $Minimum)
}
function Assert-ReplayFields($Value, [string[]]$Fields, [string]$Message) {
    Assert-Replay ($Value -is [System.Collections.IDictionary]) $Message
    Assert-Replay ($Value.Count -eq $Fields.Count -and @($Value.Keys | Where-Object { $_ -cnotin $Fields }).Count -eq 0) $Message
}
function Get-ReplaySummary($Case) {
    Assert-ReplayFields $Case @('scenario_id','synthetic','as_of_utc','max_age_seconds','future_tolerance_seconds','required_sources','observations','expected_result') 'invalid case fields'
    Assert-Replay ($Case.synthetic -is [bool] -and $Case.synthetic) 'only explicitly synthetic data is accepted'
    Assert-Replay ($Case.scenario_id -is [string] -and $Case.scenario_id -cmatch '\A[a-z][a-z0-9-]*\z') 'invalid scenario ID'
    Assert-Replay ($Case.expected_result -is [string] -and $Case.expected_result -cin @('UNKNOWN','NO_RESULTS_RETURNED','RESULTS_OBSERVED')) 'invalid expected result'
    Assert-Replay ((Test-ReplayInteger $Case.max_age_seconds 1) -and (Test-ReplayInteger $Case.future_tolerance_seconds 0)) 'invalid time budget'
    $reference = ConvertTo-ReplayUtc $Case.as_of_utc
    $required = $Case.required_sources
    Assert-Replay ($required -is [array] -and $required.Count -gt 0) 'required scope is empty'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($source in $required) {
        Assert-Replay ($source -is [string] -and $source -cmatch '\ASYNTHETIC_[A-Z0-9_]+\z') 'sources must use synthetic labels'
        Assert-Replay ($seen.Add($source)) 'duplicate required source'
    }
    Assert-Replay ($Case.observations -is [array]) 'observations must be an array'
    $observations = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $gaps = [Collections.Generic.List[string]]::new()
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($row in $Case.observations) {
        Assert-ReplayFields $row @('source','status','observed_at_utc','row_count') 'invalid observation fields'
        $source = $row.source; $status = $row.status; $count = $row.row_count
        Assert-Replay ($source -is [string] -and $seen.Contains($source)) 'unexpected source'
        Assert-Replay (!$observations.ContainsKey($source)) 'duplicate observation source'
        Assert-Replay ($status -is [string] -and $status -cin @('success','partial','accessdenied','unsupported','timedout')) 'invalid source status'
        $validCount = Test-ReplayInteger $count 0
        if ($status -ceq 'success') { Assert-Replay $validCount 'successful source requires a nonnegative row count' }
        elseif ($status -ceq 'partial') { Assert-Replay ($null -eq $count -or $validCount) 'invalid partial row count' }
        else { Assert-Replay ($null -eq $count) 'unavailable source must retain null row count' }
        $age = ($reference - (ConvertTo-ReplayUtc $row.observed_at_utc)).TotalSeconds
        if ($status -cne 'success') { $gaps.Add("${source}:$status") }
        if ($age -gt $Case.max_age_seconds) { $gaps.Add("${source}:stale") }
        if ($age -lt -$Case.future_tolerance_seconds) { $gaps.Add("${source}:future-clock-skew") }
        $observations.Add($source,$row)
    }
    foreach ($source in $required) {
        if (!$observations.ContainsKey($source)) {
            $gaps.Add("${source}:missing")
            $rows.Add(@{source=$source; status='missing'; observed_at_utc=$null; row_count=$null})
        } else { $rows.Add($observations[$source]) }
    }
    $result = 'UNKNOWN'
    if (!$gaps.Count) {
        $result = if (@($rows | Where-Object row_count -GT 0).Count) { 'RESULTS_OBSERVED' } else { 'NO_RESULTS_RETURNED' }
    }
    return [ordered]@{
        evidence_class='SYNTHETIC'; scenario_id=$Case.scenario_id; as_of_utc=$Case.as_of_utc
        result=$result; coverage_gaps=$gaps.ToArray(); sources=$rows.ToArray()
        limitation='Teaching source/window only; no live or global health assertion.'
    }
}
function Get-ReplayCases {
    $cases = ConvertFrom-KitJson (Get-Content "$PSScriptRoot\..\examples\scenarios.json" -Raw)
    Assert-Replay ($cases -is [array] -and $cases.Count -gt 0) 'fixtures must be a nonempty array'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($case in $cases) {
        $null = Get-ReplaySummary $case
        Assert-Replay ($seen.Add($case.scenario_id)) 'duplicate scenario ID'
    }
    return ,$cases
}
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $cases = Get-ReplayCases
        Assert-Replay ($Scenario -ceq 'all' -or $Scenario -cin $cases.scenario_id) 'invalid choice for scenario'
        $results = @($cases | Where-Object { $Scenario -ceq 'all' -or $_.scenario_id -ceq $Scenario } | ForEach-Object { Get-ReplaySummary $_ })
        ConvertTo-Json -InputObject $results -Depth 20
    } catch { Write-Error "Offline replay failed: $_"; exit 1 }
}
