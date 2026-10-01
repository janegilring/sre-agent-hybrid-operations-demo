#Requires -Version 5.1
[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$checks = 0
function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
    $script:checks++
}
function MustFail([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_ }
    Assert ($null -ne $caught -and $caught.ToString() -match $Pattern) "expected error: $Pattern; actual: $caught"
    $caught
}
$scratch = Join-Path $PSScriptRoot ('.offline-' + [guid]::NewGuid().ToString())
$null = New-Item $scratch -ItemType Directory
try {
    foreach ($file in Get-ChildItem $PSScriptRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1','.psd1','.psrc' }) {
        $tokens = $null; $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert (!$errors.Count) "parse $($file.Name)"
    }
    # Compile interop only. No Native method is called; both provider seams are replaced.
    Add-Type -Path "$PSScriptRoot\HybridSpoolerRecovery\Native.cs"
    $module = Import-Module "$PSScriptRoot\HybridSpoolerRecovery\HybridSpoolerRecovery.psd1" -Force -PassThru
    & $module {
        function script:Initialize-SpoolerNative {}
        function script:Read-Spooler {
            param([int]$TimeoutMs)
            if ($script:ReadError) { throw 'Injected read failure' }
            $value = $script:States[[Math]::Min($script:Reads,$script:States.Count - 1)]
            $script:Reads++
            [pscustomobject]@{ State = $value; Disabled = $script:Disabled }
        }
        function script:Request-SpoolerStart {
            $script:Starts++
            if ($script:StartError) { throw 'Injected start failure' }
            [pscustomobject]@{ IsFaulted = $false }
        }
    }
    function Scenario([string[]]$States, [bool]$Disabled = $false, [bool]$ReadError = $false, [bool]$StartError = $false) {
        & $module {
            param($States,$Disabled,$ReadError,$StartError)
            $script:States = $States; $script:Disabled = $Disabled
            $script:ReadError = $ReadError; $script:StartError = $StartError
            $script:Reads = 0; $script:Starts = 0
        } $States $Disabled $ReadError $StartError
    }
    Scenario @('Running')
    $read = Get-HybridSpoolerState
    Assert ($read.RunningVerified -and $read.ObservedUtc) 'read positive timestamp'
    $r = Start-HybridSpooler
    Assert ($r.Outcome -eq 'AlreadyRunning' -and !$r.Executed -and (& $module { $script:Starts }) -eq 0) 'idempotent running'
    Scenario @('Stopped','StartPending','Running')
    $r = Start-HybridSpooler -TimeoutSeconds 2 -Confirm:$false
    Assert ($r.Executed -and $r.Verification -eq 'Running' -and (& $module { $script:Starts }) -eq 1) 'start and verify'
    Assert ($r.CompletedUtc -and $r.ObservedUtc -and $r.DurationMs -lt 2000) 'output timing'
    Scenario @('StartPending','Running')
    $r = Start-HybridSpooler -Confirm:$false
    Assert (!$r.Executed -and $r.Verification -eq 'Running') 'wait pending without duplicate start'
    Scenario @('Stopped')
    $r = Start-HybridSpooler -WhatIf
    Assert ($r.Outcome -eq 'Planned' -and !$r.Executed -and $r.Verification -eq 'NotExecuted' -and (& $module { $script:Starts }) -eq 0) 'WhatIf never starts'
    Scenario @('Stopped') $true
    $failure = MustFail { Start-HybridSpooler -Confirm:$false } 'disabled'
    Assert ((& $module { $script:Starts }) -eq 0 -and $failure.TargetObject.Verification -eq 'Pending') 'disabled refused'
    foreach ($status in 'Paused','StopPending','Unknown','PausePending','ContinuePending') {
        Scenario @($status)
        $null = MustFail { Start-HybridSpooler -Confirm:$false } 'unsupported'
    }
    Scenario @('Stopped') $false $true
    $null = MustFail { Start-HybridSpooler -Confirm:$false } 'Injected read'
    Scenario @('Stopped') $false $false $true
    $null = MustFail { Start-HybridSpooler -Confirm:$false } 'Injected start'
    Scenario @('Stopped')
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $failure = MustFail { Start-HybridSpooler -TimeoutSeconds 1 -Confirm:$false } 'Deadline'
    Assert ($watch.Elapsed.TotalSeconds -lt 2 -and $failure.TargetObject.Outcome -eq 'TimedOut' -and
        $failure.TargetObject.Verification -eq 'Pending' -and $failure.TargetObject.CompletedUtc) 'bounded timeout pending, not success'
    $null = MustFail { Start-HybridSpooler -ServiceName 'Spooler;whoami' } 'parameter'
    $null = MustFail { Get-HybridSpoolerState -ServiceName 'WinRM' } 'parameter'
    $null = MustFail { Start-HybridSpooler -TimeoutSeconds 61 } 'greater|range'
    $null = MustFail { Start-HybridSpooler -ComputerName 'other' } 'parameter'
    . "$PSScriptRoot\Ownership.ps1"
    $sid = 'S-1-5-21-111-222-333-1001'
    $before = 'D:(D;;WP;;;WD)(A;;CCLCSW;;;AU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'
    $after = Edit-SpoolerDacl $before $sid
    Assert ((Edit-SpoolerDacl $after $sid -Remove) -ceq $before) 'exact ACE roundtrip preserves all foreign ACEs'
    $sd = [Security.AccessControl.RawSecurityDescriptor]::new($after)
    Assert ($sd.DiscretionaryAcl[3].AccessMask -eq 0x15) 'query config/status/start only'
    $null = MustFail { Edit-SpoolerDacl $after $sid } 'Existing'
    $null = MustFail { Edit-SpoolerDacl $before $sid -Remove } 'mismatch'
    $null = MustFail { Edit-SpoolerDacl ($after.Replace('CCLCRP','CCLCRPWP')) $sid -Remove } 'mismatch'
    function Invoke-SpoolerSc {
        param($Operation,$Sddl)
        if ($Operation -eq 'sdshow') { return $script:FakeDacl }
        $script:Writes++; $script:FakeDacl = $Sddl
    }
    $script:Writes = 0; $script:FakeDacl = $before
    Set-SpoolerDaclChecked $before $after
    Assert ($script:Writes -eq 1 -and $script:FakeDacl -ceq $after) 'checked ACL apply'
    $script:FakeDacl = $before.Replace('CCLCSW','CCLC')
    $null = MustFail { Set-SpoolerDaclChecked $before $after } 'Concurrent'
    Assert ($script:Writes -eq 1) 'drift blocks overwrite'
    # Execute the real installer configuration-generation command with offline paths/identities.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\Install-HybridSpoolerRecovery.ps1",[ref]$tokens,[ref]$errors)
    $command = $ast.Find({ param($node) $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'New-PSSessionConfigurationFile' },$true)
    $RecoveryRoot = $scratch; $RecoveryModule = "$PSScriptRoot\HybridSpoolerRecovery"
    $guid = [guid]::NewGuid().ToString()
    $roles = @{ 'EXAMPLE\approved-operator' = @{ RoleCapabilityFiles = "$RecoveryModule\RoleCapabilities\HybridSpoolerOperator.psrc" } }
    & ([scriptblock]::Create($command.Extent.Text))
    $config = Import-PowerShellDataFile "$scratch\Endpoint.pssc"
    Assert ($config.LanguageMode -eq 'NoLanguage' -and $config.RunAsVirtualAccount -and
        @($config.RunAsVirtualAccountGroups).Count -eq 1 -and $config.RunAsVirtualAccountGroups -eq 'HybridSpoolerOperators') 'nonadmin JEA configuration'
    $null = New-Item "$scratch\registered" -ItemType Directory
    Copy-Item "$scratch\Endpoint.pssc" "$scratch\registered\copied.pssc"
    $hash = (Get-FileHash "$scratch\Endpoint.pssc").Hash
    $endpoint = [pscustomobject]@{ Name = 'HybridSpoolerRecovery'; ConfigFilePath = "$scratch\registered\copied.pssc" }
    $record = Get-RecoveryRegistration $endpoint $hash $guid
    Assert ($record.Path -eq $endpoint.ConfigFilePath -and $record.Hash -eq $hash -and $record.Guid -eq $guid) 'actual copied registration path/hash/GUID recorded'
    $null = MustFail { Get-RecoveryRegistration $endpoint $hash ([guid]::NewGuid().ToString()) } 'GUID'
    Add-Content $endpoint.ConfigFilePath '# changed'
    $null = MustFail { Get-RecoveryRegistration $endpoint $hash $guid } 'ownership'
    $reader = Import-PowerShellDataFile "$RecoveryModule\RoleCapabilities\HybridSpoolerReader.psrc"
    Assert (@($reader.VisibleFunctions).Count -eq 1 -and $reader.VisibleFunctions -eq 'Get-HybridSpoolerState') 'read-only capability excludes write'
    "PASS: $checks offline checks on PowerShell $($PSVersionTable.PSVersion); no service/JEA/ACL operations executed."
} finally {
    Remove-Module HybridSpoolerRecovery -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
