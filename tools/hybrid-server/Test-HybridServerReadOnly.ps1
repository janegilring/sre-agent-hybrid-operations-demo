#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9.-]+$')][string]$ComputerName,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+\\[A-Za-z0-9._$-]+$')][string]$ExpectedCaller,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{1,15}$')][string]$ExpectedMachine
)
$ErrorActionPreference = 'Stop'
$session = New-PSSession -ComputerName $ComputerName -ConfigurationName HybridServer.ReadOnly -Authentication Kerberos `
    -SessionOption (New-PSSessionOption -OpenTimeout 10000 -OperationTimeout 15000 -MaximumReceivedDataSizePerCommand 262144)
try {
    $id = [guid]::NewGuid()
    $raw = Invoke-Command -Session $session -ScriptBlock { Get-HybridServerFacts -CorrelationId $using:id }
    $facts = $raw | ConvertFrom-Json
    if ($facts.IsAdministrator -ne $false -or $facts.Machine -ine $ExpectedMachine -or
        $facts.ConnectingIdentity -ine $ExpectedCaller -or $facts.CorrelationId -ne $id.ToString('D') -or
        $facts.ExecutionIdentity -notlike 'WinRM Virtual Users\WinRM VA_*') { throw 'Identity validation failed.' }
    Invoke-Command -Session $session -ScriptBlock { Get-HybridServerServiceState -CorrelationId $using:id -Service Spooler }
    Invoke-Command -Session $session -ScriptBlock { Get-HybridServerEvents -CorrelationId $using:id -Log System -MaxCount 5 -LookbackMinutes 60 }
    foreach ($probe in @(
        { Get-Service Spooler },
        { Get-HybridServerServiceState -CorrelationId $using:id -Service WinRM },
        { Get-HybridServerEvents -CorrelationId $using:id -Log Security -MaxCount 5 -LookbackMinutes 60 },
        { Get-HybridServerEvents -CorrelationId $using:id -Log System -MaxCount 51 -LookbackMinutes 60 },
        { Get-HybridServerEvents -CorrelationId $using:id -Log System -MaxCount 5 -LookbackMinutes 1441 },
        { Get-HybridServerFacts -CorrelationId $using:id -ComputerName other }
    )) {
        $denied = $false
        try { $null = Invoke-Command -Session $session -ScriptBlock $probe -ErrorAction Stop } catch { $denied = $true }
        if (!$denied) { throw 'Negative capability test unexpectedly succeeded.' }
    }
    $facts
} finally { Remove-PSSession $session }
