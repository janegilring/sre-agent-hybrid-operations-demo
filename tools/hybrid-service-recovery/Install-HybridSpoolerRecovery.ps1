#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][ValidatePattern('^[\w.-]+\\[\w.$-]+$')][string]$CallerIdentity,
    [ValidatePattern('^[\w.-]+\\[\w.$-]+$')][string]$ReaderIdentity
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ownership.ps1"
if ($PSVersionTable.PSEdition -ne 'Desktop' -or ![Environment]::Is64BitProcess) { throw 'Use 64-bit Windows PowerShell 5.1.' }
if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) { throw 'Domain controllers are unsupported.' }
$sids = @{}
foreach ($identity in @($CallerIdentity,$ReaderIdentity) | Where-Object { $_ }) {
    $sid = ([Security.Principal.NTAccount]::new($identity)).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-(\d+)$' -or [long]$Matches[1] -lt 1000) { throw 'Dedicated caller account/group required; built-in/broad identities refused.' }
    if ($sids.Values -contains $sid) { throw 'Reader and operator must be distinct identities.' }
    $sids[$identity] = $sid
}
if ((Test-Path $RecoveryRoot) -or (Test-Path $RecoveryModule) -or
    (Get-LocalGroup $RecoveryGroup -ErrorAction SilentlyContinue) -or
    (Get-PSSessionConfiguration -Name $RecoveryEndpoint -ErrorAction SilentlyContinue)) { throw 'Ownership collision; nothing changed.' }
$before = Invoke-SpoolerSc sdshow
if (!$PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install $RecoveryEndpoint and Spooler-only start ACL for $CallerIdentity")) { return }
$guid = [guid]::NewGuid().ToString()
$runtime = New-LocalGroup -Name $RecoveryGroup -Description "HybridSpoolerRecovery:$guid"
foreach ($path in @($RecoveryRoot,$RecoveryModule)) {
    $null = New-Item $path -ItemType Directory
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
    }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $runtime.SID,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
    Set-Acl $path $acl
}
Copy-Item "$PSScriptRoot\HybridSpoolerRecovery\*" $RecoveryModule -Recurse
$roles = @{ $CallerIdentity = @{ RoleCapabilityFiles = "$RecoveryModule\RoleCapabilities\HybridSpoolerOperator.psrc" } }
if ($ReaderIdentity) { $roles[$ReaderIdentity] = @{ RoleCapabilityFiles = "$RecoveryModule\RoleCapabilities\HybridSpoolerReader.psrc" } }
$endpointSddl = "O:BAG:BAD:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GX;;;$($sids[$CallerIdentity]))"
if ($ReaderIdentity) { $endpointSddl += "(A;;GX;;;$($sids[$ReaderIdentity]))" }
New-PSSessionConfigurationFile -Path "$RecoveryRoot\Endpoint.pssc" -Guid $guid -SessionType RestrictedRemoteServer `
    -LanguageMode NoLanguage -RunAsVirtualAccount -RunAsVirtualAccountGroups $RecoveryGroup `
    -ModulesToImport "$RecoveryModule\HybridSpoolerRecovery.psd1" -RoleDefinitions $roles
$after = Edit-SpoolerDacl $before $runtime.SID.Value
$files = @{}
Get-ChildItem $RecoveryRoot,$RecoveryModule -Recurse -File | ForEach-Object { $files[$_.FullName] = (Get-FileHash $_.FullName).Hash }
$receipt = [pscustomobject]@{ Schema = 1; Endpoint = $RecoveryEndpoint; Guid = $guid; GroupSid = $runtime.SID.Value
    Resource = 'Spooler'; Rights = 0x15; Before = $before; After = $after
    BeforeHash = (Get-TextHash $before); AfterHash = (Get-TextHash $after)
    Files = $files; Directories = @(Get-ChildItem $RecoveryRoot,$RecoveryModule -Recurse -Directory | Select-Object -ExpandProperty FullName)
    Registration = $null; Phase = 'Prepared'; CallerSids = $sids }
$receipt | ConvertTo-Json -Depth 6 | Set-Content "$RecoveryRoot\Ownership.json" -Encoding UTF8
Set-SpoolerDaclChecked $before $after
$receipt.Phase = 'AclGranted'
$receipt | ConvertTo-Json -Depth 6 | Set-Content "$RecoveryRoot\Ownership.json" -Encoding UTF8
if (Get-PSSessionConfiguration -Name $RecoveryEndpoint -ErrorAction SilentlyContinue) { throw 'Endpoint appeared concurrently; registration refused.' }
Register-PSSessionConfiguration -Name $RecoveryEndpoint -Path "$RecoveryRoot\Endpoint.pssc" `
    -SecurityDescriptorSddl $endpointSddl -NoServiceRestart -Force
$receipt.Registration = Get-RecoveryRegistration (Get-PSSessionConfiguration -Name $RecoveryEndpoint) `
    $files["$RecoveryRoot\Endpoint.pssc"] $guid
$receipt.Phase = 'Registered'
$receipt | ConvertTo-Json -Depth 6 | Set-Content "$RecoveryRoot\Ownership.json" -Encoding UTF8
'Installed; no service start or WinRM restart performed. Operator must schedule activation and real nonadmin validation. No SRE wiring.'
