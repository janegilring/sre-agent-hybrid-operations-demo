#Requires -Version 5.1
Set-StrictMode -Version Latest
function Read-Spooler([int]$TimeoutMs = 5000) {
    $task = [HybridSpoolerRecovery.Native]::BeginRead()
    if (!$task.Wait($TimeoutMs)) { throw 'State query deadline exceeded; verification pending.' }
    $task.Result
}
function Request-SpoolerStart { ,([HybridSpoolerRecovery.Native]::BeginStart()) }
function Initialize-SpoolerNative {
    if (-not ('HybridSpoolerRecovery.Native' -as [type])) {
        Add-Type -Path "$PSScriptRoot\Native.cs" -ErrorAction Stop
    }
}
function Get-HybridSpoolerState {
    [CmdletBinding()] param()
    Initialize-SpoolerNative
    $state = Read-Spooler
    [pscustomobject]@{ Service = 'Spooler'; State = $state.State; Disabled = $state.Disabled
        ObservedUtc = [datetime]::UtcNow.ToString('o'); RunningVerified = ($state.State -eq 'Running') }
}
function Start-HybridSpooler {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([ValidateRange(1,60)][int]$TimeoutSeconds = 15)
    $result = [pscustomobject]@{ Service = 'Spooler'; Outcome = 'Error'; Executed = $false
        State = 'Unknown'; Verification = 'Pending'; RequestedUtc = [datetime]::UtcNow.ToString('o')
        ObservedUtc = $null; CompletedUtc = $null; DurationMs = 0; Error = $null }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        Initialize-SpoolerNative
        $clock.Restart()
        $state = Read-Spooler -TimeoutMs ($TimeoutSeconds * 1000)
        $result.State = $state.State; $result.ObservedUtc = [datetime]::UtcNow.ToString('o')
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw 'State query deadline exceeded; verification pending.' }
        if ($state.Disabled) { throw 'Spooler is disabled; changing startup configuration is forbidden.' }
        if ($state.State -eq 'Running') {
            $result.Outcome = 'AlreadyRunning'; $result.Verification = 'Running'
        } elseif ($state.State -notin @('Stopped','StartPending')) {
            throw "Refusing unsupported Spooler state: $($state.State)."
        } else {
            $clock.Stop()
            $approved = $PSCmdlet.ShouldProcess('local Spooler', 'Start and verify Running')
            $clock.Start()
            if (!$approved) {
                $result.Outcome = 'Planned'; $result.Verification = 'NotExecuted'
                $result.CompletedUtc = [datetime]::UtcNow.ToString('o'); $result.DurationMs = $clock.ElapsedMilliseconds
                return $result
            }
            $task = $null
            if ($state.State -eq 'Stopped') { $task = Request-SpoolerStart; $result.Executed = $true }
            while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
                if ($null -ne $task -and $task.IsFaulted) { throw $task.Exception.GetBaseException() }
                $remaining = [int][Math]::Max(1,($TimeoutSeconds * 1000 - $clock.ElapsedMilliseconds))
                $state = Read-Spooler -TimeoutMs $remaining
                $result.State = $state.State; $result.ObservedUtc = [datetime]::UtcNow.ToString('o')
                if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
                if ($state.Disabled) { throw 'Spooler became disabled; no configuration change attempted.' }
                if ($state.State -eq 'Running') {
                    $result.Outcome = 'Running'; $result.Verification = 'Running'; break
                }
                Start-Sleep -Milliseconds 100
            }
            if ($result.Verification -ne 'Running') {
                $result.Outcome = 'TimedOut'
                throw 'Deadline exceeded; Running is NOT verified. An issued start may still complete; inspect before retry.'
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
        $result.CompletedUtc = [datetime]::UtcNow.ToString('o'); $result.DurationMs = $clock.ElapsedMilliseconds
        $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
            $_.Exception, 'HybridSpoolerRecoveryFailed', [Management.Automation.ErrorCategory]::InvalidResult, $result))
    }
    $result.CompletedUtc = [datetime]::UtcNow.ToString('o'); $result.DurationMs = $clock.ElapsedMilliseconds
    $result
}
Export-ModuleMember -Function Get-HybridSpoolerState,Start-HybridSpooler
