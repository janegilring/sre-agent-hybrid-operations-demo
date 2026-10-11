#Requires -Version 7.5
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Read-StrictJson.ps1"

function Assert-That([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    try { $null = & $Action } catch {
        Assert-That ($_.Exception.Message -match $Pattern) "Unexpected rejection: $_"
        return
    }
    throw "FAIL: expected rejection matching $Pattern"
}
function Copy-JsonValue($Value) {
    ConvertFrom-KitJson (ConvertTo-Json -InputObject $Value -Depth 100 -Compress)
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
    function ConvertTo-Canonical($Value) {
        if ($Value -is [System.Collections.IDictionary]) {
            $result = [ordered]@{}
            foreach ($key in ($Value.Keys | Sort-Object -CaseSensitive)) { $result[$key] = ConvertTo-Canonical $Value[$key] }
            return $result
        }
        if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-Canonical $_ }) }
        return $Value
    }
    $left = ConvertTo-Json -InputObject (ConvertTo-Canonical $Actual) -Depth 100 -Compress
    $right = ConvertTo-Json -InputObject (ConvertTo-Canonical $Expected) -Depth 100 -Compress
    Assert-That ($left -ceq $right) "$Message`nActual: $left`nExpected: $right"
}
function Read-TestJson([string]$Path) {
    ConvertFrom-KitJson (Get-Content -LiteralPath $Path -Raw)
}
function Get-CompiledTemplate([string]$Path) {
    $output = & bicep build $Path --stdout
    if ($LASTEXITCODE -ne 0) { throw "Bicep compilation failed: $Path" }
    ConvertFrom-KitJson ($output -join "`n")
}
