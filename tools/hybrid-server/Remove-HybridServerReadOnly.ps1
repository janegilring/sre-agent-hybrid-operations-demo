#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ownership.ps1"
$root = 'C:\ProgramData\HybridServerReadOnly'
$module = 'C:\Program Files\WindowsPowerShell\Modules\HybridServerReadOnly'
$group = Get-LocalGroup HybridServerReaders
$state = Get-Content "$root\Ownership.json" -Raw | ConvertFrom-Json
if ($state.Owner -ne 'HybridServerReadOnly:1ec52169-b20b-4094-9937-2adb96c98d85' -or
    $group.Description -ne $state.Owner -or $group.SID.Value -ne $state.GroupSid -or
    @(Get-LocalGroupMember $group).Count -ne 0) { throw 'Ownership/group drift; no removal.' }
$actual = @(Get-ChildItem $root,$module -Recurse -File -Force | Where-Object { $_.FullName -ne "$root\Ownership.json" })
if (@(Get-Item $root,$module | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -or
    @(Get-ChildItem $root,$module -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Reparse point refused.' }
if (@(Compare-Object @($state.Directories) @(Get-ChildItem $root,$module -Recurse -Directory -Force | Select-Object -ExpandProperty FullName)).Count) {
    throw 'Foreign directories found; no removal.'
}
if ($actual.Count -ne @($state.Files.PSObject.Properties).Count) { throw 'Foreign files found; no removal.' }
foreach ($file in $actual) {
    $expected = $state.Files.PSObject.Properties[$file.FullName]
    if (!$expected -or (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne $expected.Value) { throw 'File drift; no removal.' }
}
$endpoint = Get-PSSessionConfiguration -Name HybridServer.ReadOnly -ErrorAction SilentlyContinue
$sourceHash = Assert-HybridOwnedConfiguration $state $root $module
if ($endpoint) {
    if ($state.RegistrationState -ne 'Registered' -or !$state.Registration) {
        throw 'Unconfirmed registration after partial installation; no removal.'
    }
    $registered = Get-HybridRegistrationRecord $endpoint $sourceHash $state.ConfigurationGuid
    foreach ($field in 'Name','ConfigFilePath','ConfigurationGuid','Sha256') {
        if ($registered.$field -ine $state.Registration.$field) { throw 'Foreign endpoint configuration; no removal.' }
    }
}
if (!$PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove only owned HybridServer.ReadOnly endpoint, unchanged files and empty local group')) { return }
if ($endpoint) { Unregister-PSSessionConfiguration -Name HybridServer.ReadOnly -NoServiceRestart -Force }
# No provider ACLs or group memberships are added by this installer, so none are removed.
Remove-Item $root,$module -Recurse
Remove-LocalGroup -Name HybridServerReaders
Write-Output 'Owned resources removed. Schedule WinRM restart. Independently owned provider grants were not changed.'
