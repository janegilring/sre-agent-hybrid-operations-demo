#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]{1,64}\\[A-Za-z0-9._$-]{1,64}$')][string]$CallerIdentity)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ownership.ps1"
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Install using Windows PowerShell 5.1 (WSMan JEA).' }
if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) { throw 'Domain controllers are not supported.' }
$root = 'C:\ProgramData\HybridServerReadOnly'
$module = 'C:\Program Files\WindowsPowerShell\Modules\HybridServerReadOnly'
$endpoint = 'HybridServer.ReadOnly'
$group = 'HybridServerReaders'
$owner = 'HybridServerReadOnly:1ec52169-b20b-4094-9937-2adb96c98d85'
$groupDescription = 'HybridJEA:1ec52169-b20b-4094-9937-2adb96c98d85'
$callerSid = ([Security.Principal.NTAccount]::new($CallerIdentity)).Translate([Security.Principal.SecurityIdentifier])
if ($callerSid.Value -in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-1-0')) { throw 'Explicit dedicated caller identity/group required.' }
if ((Test-Path $root) -or (Test-Path $module) -or
    (Get-PSSessionConfiguration -Name $endpoint -ErrorAction SilentlyContinue) -or
    (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) { throw 'Ownership collision: no resources changed.' }
if (!$PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install $endpoint for $CallerIdentity; create isolated nonadmin runtime group (no provider grants)")) { return }
$runtime = New-LocalGroup -Name $group -Description $groupDescription
$null = New-Item $root -ItemType Directory
$null = New-Item $module -ItemType Directory
foreach ($path in @($root,$module)) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($runtime.SID,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
    Set-Acl $path $acl
}
Copy-Item "$PSScriptRoot\HybridServerReadOnly\*" $module -Recurse
'$global:HybridServerConnectingIdentity = [string]$PSSenderInfo.UserInfo.Identity.Name' |
    Set-Content "$root\Initialize.ps1" -Encoding UTF8
$configurationGuid = [guid]::NewGuid()
& "$PSScriptRoot\New-HybridServerConfiguration.ps1" -Path "$root\Endpoint.pssc" -CallerIdentity $CallerIdentity -ConfigurationGuid $configurationGuid `
    -ModulePath $module -InitializePath "$root\Initialize.ps1" -Confirm:$false
$files = @{}
Get-ChildItem $root,$module -Recurse -File | ForEach-Object { $files[$_.FullName] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash }
$receipt = @{ SchemaVersion = 2; Owner = $owner; GroupDescription = $groupDescription; GroupSid = $runtime.SID.Value; CallerSid = $callerSid.Value
    CallerIdentity = $CallerIdentity; EndpointName = $endpoint; ConfigurationGuid = $configurationGuid.ToString('D')
    RegistrationState = 'Pending'; Registration = $null; Files = $files
    Directories = @(Get-ChildItem $root,$module -Recurse -Directory | Select-Object -ExpandProperty FullName) } |
    ConvertTo-Json -Depth 5 | ConvertFrom-Json
$receipt | ConvertTo-Json -Depth 5 | Set-Content "$root\Ownership.json" -Encoding UTF8
# A failed/ambiguous registration leaves Pending on disk, never a guessed ownership claim.
Register-PSSessionConfiguration -Name $endpoint -Path "$root\Endpoint.pssc" -NoServiceRestart -Force
$sourceHash = Assert-HybridOwnedConfiguration $receipt $root $module
$receipt.Registration = Get-HybridRegistrationRecord (Get-PSSessionConfiguration -Name $endpoint) $sourceHash $receipt.ConfigurationGuid
$receipt.RegistrationState = 'Registered'
$receipt | ConvertTo-Json -Depth 5 | Set-Content "$root\Ownership.json" -Encoding UTF8
Write-Output 'Installed without restarting WinRM. Schedule a WinRM restart, then run validation. No provider ACLs or memberships were granted.'
