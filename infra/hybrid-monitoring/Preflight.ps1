#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$WorkspaceResourceId,
    [Parameter(Mandatory)][string]$TargetsPath,
    [Parameter(Mandatory)][string]$ConfigPath
)
. "$PSScriptRoot\Common.ps1"
$inputs = Read-Inputs $SubscriptionId $WorkspaceResourceId $TargetsPath $ConfigPath
$work = New-WorkDirectory
try { Test-LiveCoverage $inputs $work }
finally { Remove-Item -LiteralPath $work -Recurse -Force }
