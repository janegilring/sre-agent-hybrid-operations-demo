#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]{1,64}\\[A-Za-z0-9._$-]{1,64}$')][string]$CallerIdentity,
    [Parameter(Mandatory)][string]$ModulePath,
    [Parameter(Mandatory)][string]$InitializePath,
    [guid]$ConfigurationGuid = [guid]::NewGuid()
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Path) { throw 'Refusing to overwrite an existing configuration.' }
$roleFile = Join-Path $ModulePath 'RoleCapabilities\HybridServerReader.psrc'
if (!(Test-Path -LiteralPath $roleFile -PathType Leaf) -or !(Test-Path -LiteralPath $InitializePath -PathType Leaf)) {
    throw 'Reviewed role capability and initialization files are required.'
}
$roles = @{}
$roles[$CallerIdentity] = @{ RoleCapabilityFiles = (Resolve-Path -LiteralPath $roleFile).Path }
if (!$PSCmdlet.ShouldProcess($Path, 'Generate nonadministrator NoLanguage JEA configuration only; do not register')) { return }
New-PSSessionConfigurationFile -Path $Path -Guid $ConfigurationGuid `
    -Author 'NIC demo contributors' `
    -SessionType RestrictedRemoteServer -LanguageMode NoLanguage -RunAsVirtualAccount `
    -RunAsVirtualAccountGroups HybridServerReaders -RoleDefinitions $roles -ModulesToImport HybridServerReadOnly `
    -ScriptsToProcess (Resolve-Path -LiteralPath $InitializePath).Path -VisibleAliases @() `
    -VisibleCmdlets @() -VisibleFunctions @() -VisibleExternalCommands @() -VisibleProviders @()
if (!(Test-PSSessionConfigurationFile -Path $Path)) { throw 'Generated configuration invalid.' }
