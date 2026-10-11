#Requires -Version 7.5
. "$PSScriptRoot\..\scripts\TestSupport.ps1"
. "$PSScriptRoot\..\scripts\Invoke-Replay.ps1"
$cases = Get-ReplayCases
$empty = Copy-JsonValue ($cases | Where-Object scenario_id -EQ 'complete-empty')
foreach ($case in $cases) {
    $result = Get-ReplaySummary $case
    Assert-Equal $result.result $case.expected_result 'fixture answer'
    Assert-Equal $result.evidence_class 'SYNTHETIC' 'evidence class'
    Assert-Equal $result.sources.Count $case.required_sources.Count 'source count'
    Assert-Equal @($result.Keys | Sort-Object) @('evidence_class','scenario_id','as_of_utc','result','coverage_gaps','sources','limitation' | Sort-Object) 'output shape'
    if ($case.scenario_id -in @('provider-denied','missing-source')) {
        Assert-Equal $result.result 'UNKNOWN' 'incomplete result'
        Assert-That ($null -eq $result.sources[1].row_count -and $result.coverage_gaps.Count -gt 0) 'missing count remains null'
    }
    if ($case.scenario_id -eq 'partial-source') {
        Assert-Equal $result.result 'UNKNOWN' 'partial result'
        Assert-Equal $result.sources[0].row_count 1 'partial count retained'
    }
}
$empty.expected_result = 'UNKNOWN'
Assert-Equal (Get-ReplaySummary $empty).result 'NO_RESULTS_RETURNED' 'answer key ignored'
foreach ($boundary in @(
    @('2000-01-01T00:00:00Z','NO_RESULTS_RETURNED'), @('1999-12-31T23:59:59Z','UNKNOWN'),
    @('2000-01-01T00:02:05Z','NO_RESULTS_RETURNED'), @('2000-01-01T00:02:06Z','UNKNOWN')
)) {
    $case = Copy-JsonValue $empty; $case.observations[0].observed_at_utc = $boundary[0]
    Assert-Equal (Get-ReplaySummary $case).result $boundary[1] 'freshness boundary'
}
foreach ($timestamp in @('', 'invalid','2000-01-01T00:01:00','2000-01-01T01:01:00+01:00',$null)) {
    $case = Copy-JsonValue $empty; $case.observations[0].observed_at_utc = $timestamp
    Assert-Rejected { Get-ReplaySummary $case } 'timestamp'
}
foreach ($status in @('accessdenied','unsupported','timedout')) {
    $case = Copy-JsonValue $empty; $case.observations[0].status=$status; $case.observations[0].row_count=$null
    Assert-Equal (Get-ReplaySummary $case).result 'UNKNOWN' 'unavailable status'
}
foreach ($count in @(-1,$true,'0',0.5,$null)) {
    $case = Copy-JsonValue $empty; $case.observations[0].row_count = $count
    Assert-Rejected { Get-ReplaySummary $case } 'row count'
}
$mutations = @(
    { param($c) $c.synthetic=$false }, { param($c) $c.required_sources=@() },
    { param($c) $c.required_sources+= $c.required_sources[0] },
    { param($c) $c.observations+= (Copy-JsonValue $c.observations[0]) },
    { param($c) $c.observations[0].source='NOT_SYNTHETIC' },
    { param($c) $c.observations[0].status='accessdenied'; $c.observations[0].row_count=0 },
    { param($c) $c.max_age_seconds=$true }, { param($c) $c.future_tolerance_seconds=-1 },
    { param($c) $c.unrecognized='field' }, { param($c) $c.expected_result='unknown' },
    { param($c) $c.observations[0].status='SUCCESS' }, { param($c) $c.synthetic='true' }
)
foreach ($mutation in $mutations) {
    $case=Copy-JsonValue $empty; & $mutation $case
    Assert-Rejected { Get-ReplaySummary $case } 'synthetic|scope|duplicate|unexpected|row count|time budget|fields|result|status'
}
$valid = & pwsh -NoProfile -File "$PSScriptRoot\..\scripts\Invoke-Replay.ps1" -Scenario all
Assert-That ($LASTEXITCODE -eq 0) 'CLI success'
Assert-Equal @(ConvertFrom-Json -InputObject ($valid -join "`n")).Count $cases.Count 'CLI array'
$scratch = Join-Path ([IO.Path]::GetTempPath()) "replay-$([guid]::NewGuid()).txt"
try {
    $invalid = & pwsh -NoProfile -File "$PSScriptRoot\..\scripts\Invoke-Replay.ps1" -Scenario not-a-case 2> $scratch
    Assert-That ($LASTEXITCODE -ne 0 -and !$invalid) 'CLI rejection has no success stdout'
    Assert-That ((Get-Content $scratch -Raw) -match 'invalid choice') 'CLI diagnostic'
} finally { Remove-Item -LiteralPath $scratch }
'PASS: replay fixtures, output/null contracts, freshness, all prior rejecting mutations and CLI behavior.'
