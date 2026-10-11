#Requires -Version 7.5
[CmdletBinding()]
param([string]$ParametersPath, [string]$SubscriptionId)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\..\scripts\Read-StrictJson.ps1"

function Get-ArcAlertName([string]$Owner, [string]$MachineId) {
    # ARM guid() is UUIDv5 over hyphen-joined arguments with this fixed namespace.
    $namespace = [Convert]::FromHexString('11fb06fb712d4ddd98c7e71bbd588830')
    $name = [Text.Encoding]::UTF8.GetBytes($Owner.ToLowerInvariant() + '-' + $MachineId.ToLowerInvariant())
    $hash = [Security.Cryptography.SHA1]::HashData([byte[]]($namespace + $name))
    $hash[6] = ($hash[6] -band 0x0f) -bor 0x50
    $hash[8] = ($hash[8] -band 0x3f) -bor 0x80
    $hex = [Convert]::ToHexString($hash[0..15]).ToLowerInvariant()
    return 'arc-connectivity-single-' + ($hex -replace '^(.{8})(.{4})(.{4})(.{4})(.{12})$', '$1-$2-$3-$4-$5')
}
function Test-ArcParameters($Parameters, $SubscriptionId) {
    $subscription = [guid]::Empty
    if ($SubscriptionId -isnot [string] -or ![guid]::TryParse($SubscriptionId,[ref]$subscription)) {
        throw 'Expected an explicit subscription UUID'
    }
    if ($Parameters -isnot [Collections.IDictionary] -or !$Parameters.Contains('parameters')) { throw 'Expected an ARM parameters document' }
    $entries = $Parameters.parameters
    if ($entries -isnot [Collections.IDictionary] -or @($entries.Keys | Where-Object { $_ -cnotin @('ownershipId','machineResourceIds','actionGroupResourceIds') }).Count) { throw 'Unexpected parameters' }
    $values = @{}
    foreach ($key in $entries.Keys) {
        $entry = $entries[$key]
        if ($entry -isnot [Collections.IDictionary] -or $entry.Count -ne 1 -or @($entry.Keys)[0] -cne 'value') { throw "$key must contain one literal value" }
        $values[$key] = $entry.value
    }
    $guidPattern = '[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}'
    $owner = $values['ownershipId']
    if ($owner -isnot [string] -or $owner -notmatch "\A$guidPattern\z") { throw 'ownershipId must be a canonical UUID' }
    if ([guid]$owner -eq [guid]::Empty) { throw 'ownershipId must not be the nil UUID' }
    foreach ($kind in @(
        @('machineResourceIds','Microsoft.HybridCompute/machines',$true),
        @('actionGroupResourceIds','Microsoft.Insights/actionGroups',$false)
    )) {
        $key,$type,$required = $kind
        $ids = $null
        if ($values.ContainsKey($key)) { $ids = $values[$key] } elseif (!$required) { $ids = @() }
        if ($ids -isnot [array] -or ($required -and !$ids.Count)) { throw "$key must be an array with the required IDs" }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($id in $ids) {
            if ($id -isnot [string] -or $id -notmatch "\A/subscriptions/(?<subscription>$guidPattern)/resourceGroups/[A-Za-z0-9_.()-]+/providers/(?<type>[^/]+/[^/]+)/[A-Za-z0-9_.()-]+\z" -or $Matches.type -ine $type) { throw "$key requires exact $type IDs with nonempty names" }
            if ($Matches.subscription -ine $subscription.ToString()) { throw "$key must be in the explicitly selected subscription" }
            if (!$seen.Add($id)) { throw "$key contains duplicate IDs" }
        }
    }
    foreach ($id in $values.machineResourceIds) { Get-ArcAlertName $owner $id }
}
if ($MyInvocation.InvocationName -ne '.') {
    if (!$ParametersPath -or !$SubscriptionId) { throw 'ParametersPath and SubscriptionId are required' }
    $document = ConvertFrom-KitJson (Get-Content -LiteralPath $ParametersPath -Raw)
    $names = @(Test-ArcParameters $document $SubscriptionId)
    "PASS: input shape only; $($names.Count) proposed alerts: $($names -join ', ')"
    'Existence, Resource Health support, ownership absence, permissions and exactly one Create per machine still require fresh read-only preflight.'
}
