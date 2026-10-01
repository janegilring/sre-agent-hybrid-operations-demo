#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ownership.ps1"
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell 5.1.' }
$receipt = Get-Content "$RecoveryRoot\Ownership.json" -Raw | ConvertFrom-Json
if ($receipt.Schema -ne 1 -or $receipt.Endpoint -cne $RecoveryEndpoint -or
    $receipt.Resource -cne 'Spooler' -or $receipt.Rights -ne 0x15 -or
    [guid]$receipt.Guid -eq [guid]::Empty -or
    $receipt.Phase -notin @('Prepared','AclGranted','Registered') -or
    (Get-TextHash $receipt.Before) -cne $receipt.BeforeHash -or
    (Get-TextHash $receipt.After) -cne $receipt.AfterHash -or
    (Edit-SpoolerDacl $receipt.After $receipt.GroupSid -Remove) -cne $receipt.Before) { throw 'Invalid ownership receipt.' }
$group = Get-LocalGroup $RecoveryGroup
if ($group.SID.Value -cne $receipt.GroupSid -or $group.Description -cne "HybridSpoolerRecovery:$($receipt.Guid)" -or
    @(Get-LocalGroupMember $RecoveryGroup).Count) { throw 'Runtime group ownership/membership changed.' }
foreach ($file in $receipt.Files.PSObject.Properties) {
    if (!$file.Name.StartsWith("$RecoveryRoot\",'OrdinalIgnoreCase') -and
        !$file.Name.StartsWith("$RecoveryModule\",'OrdinalIgnoreCase')) { throw 'Invalid owned file path.' }
    Assert-RecoveryFile $file.Name $file.Value
}
$actualFiles = @(Get-ChildItem $RecoveryRoot,$RecoveryModule -Recurse -File | Where-Object { $_.FullName -ine "$RecoveryRoot\Ownership.json" })
if ($actualFiles.Count -ne @($receipt.Files.PSObject.Properties).Count) { throw 'Unexpected files; no cleanup.' }
$directories = @(Get-ChildItem $RecoveryRoot,$RecoveryModule -Recurse -Directory)
if (@($directories | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -or
    (@($directories.FullName | Sort-Object) -join '|') -cne (@($receipt.Directories | Sort-Object) -join '|')) {
    throw 'Unexpected directories; no cleanup.'
}
$sourceHash = $receipt.Files.PSObject.Properties["$RecoveryRoot\Endpoint.pssc"].Value
$endpoint = Get-PSSessionConfiguration -Name $RecoveryEndpoint -ErrorAction SilentlyContinue
if ($endpoint) {
    $registration = Get-RecoveryRegistration $endpoint $sourceHash $receipt.Guid
    if ($receipt.Registration -and ($registration.Path -ine $receipt.Registration.Path -or
        $registration.Hash -cne $receipt.Registration.Hash -or $registration.Guid -cne $receipt.Registration.Guid)) {
        throw 'Registered configuration identity changed; no cleanup.'
    }
}
$current = Invoke-SpoolerSc sdshow
if ($current -cne $receipt.After -and $current -cne $receipt.Before) { throw 'Service DACL drift; no cleanup. Preserve foreign ACEs and investigate.' }
if (!$PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove exact-owned recovery endpoint, ACE, module and empty group')) { return }
if ($endpoint) { Unregister-PSSessionConfiguration -Name $RecoveryEndpoint -NoServiceRestart -Force }
if ($current -ceq $receipt.After) { Set-SpoolerDaclChecked $current (Edit-SpoolerDacl $current $receipt.GroupSid -Remove) }
Remove-LocalGroup -SID $group.SID
foreach ($file in $receipt.Files.PSObject.Properties) { Remove-Item -LiteralPath $file.Name }
Remove-Item -LiteralPath "$RecoveryRoot\Ownership.json"
$receipt.Directories | Sort-Object Length -Descending | ForEach-Object { [IO.Directory]::Delete($_) }
[IO.Directory]::Delete($RecoveryModule); [IO.Directory]::Delete($RecoveryRoot)
'Removed owned resources; no Spooler state change or WinRM restart. Terminate existing sessions in the approved maintenance window.'
