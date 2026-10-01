Set-StrictMode -Version Latest

function ConvertTo-HybridText {
    param($Value, [int]$Limit = 160)
    if ($null -eq $Value) { return $null }
    $text = [regex]::Replace([string]$Value, '[\x00-\x1f\x7f-\x9f]', ' ')
    if ($text.Length -gt $Limit) { $text = $text.Substring(0, $Limit) }
    $text
}

function New-HybridContext {
    param([guid]$CorrelationId, [string]$Operation)
    if ($CorrelationId -eq [guid]::Empty) { throw 'Correlation required.' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if ($identity.IsSystem -or $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
            $identity.Groups.Contains([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')) -or
            $principal.IsInRole([Security.Principal.SecurityIdentifier]::new('S-1-5-32-578')) -or
            $identity.Name -notlike 'WinRM Virtual Users\WinRM VA_*') { throw 'Nonadministrator JEA execution required.' }
        $caller = [string]$global:HybridServerConnectingIdentity
        if ([string]::IsNullOrWhiteSpace($caller)) { throw 'Connecting identity unavailable.' }
        [ordered]@{
            SchemaVersion = 1; Operation = $Operation; Machine = [Environment]::MachineName
            Domain = [Environment]::UserDomainName; OsVersion = [Environment]::OSVersion.Version.ToString()
            ConnectingIdentity = $caller; ExecutionIdentity = $identity.Name; IsAdministrator = $false
            CorrelationId = $CorrelationId.ToString('D'); AsOfUtc = [DateTimeOffset]::UtcNow.ToString('o')
            Providers = @()
        }
    } finally { $identity.Dispose() }
}

function Read-HybridProvider {
    param([string]$Source, [int]$Limit, [scriptblock]$Query, [switch]$RequireRow)
    $start = [DateTimeOffset]::UtcNow.ToString('o')
    try {
        $rows = @(& $Query | Microsoft.PowerShell.Utility\Select-Object -First ($Limit + 1))
        if ($RequireRow -and $rows.Count -eq 0) { throw 'Missing provider observation.' }
        $truncated = $rows.Count -gt $Limit
        [ordered]@{
            Source = $Source; Status = $(if ($truncated) { 'partial' } else { 'success' })
            AsOfUtc = $start; CompletedUtc = [DateTimeOffset]::UtcNow.ToString('o')
            ErrorCode = $(if ($truncated) { 'RowLimit' } else { $null })
            Limit = $Limit; Truncated = $truncated
            Rows = @($rows | Microsoft.PowerShell.Utility\Select-Object -First $Limit)
        }
    } catch {
        $denied = $_.CategoryInfo.Category -eq 'PermissionDenied'
        $exception = $_.Exception
        for ($depth = 0; $null -ne $exception -and $depth -lt 4; $depth++) {
            if ($exception.HResult -in @(-2147024891,-2147217405) -or
                ($exception -is [ComponentModel.Win32Exception] -and $exception.NativeErrorCode -eq 5)) { $denied = $true }
            $exception = $exception.InnerException
        }
        [ordered]@{
            Source = $Source; Status = $(if ($denied) { 'denied' } else { 'unknown' })
            AsOfUtc = $start; CompletedUtc = [DateTimeOffset]::UtcNow.ToString('o')
            ErrorCode = $(if ($denied) { 'ProviderAccessDenied' } else { 'ProviderFailure' })
            Limit = $Limit; Truncated = $false; Rows = @()
        }
    }
}

function Complete-HybridRead {
    param($Context)
    $Context.CompletedUtc = [DateTimeOffset]::UtcNow.ToString('o')
    $json = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $Context -Depth 10 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 131072) { throw 'Response size exceeded.' }
    $json
}

function Get-HybridServerFacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][guid]$CorrelationId)
    $ErrorActionPreference = 'Stop'
    $r = New-HybridContext $CorrelationId 'facts'
    $r.Providers = @(
        Read-HybridProvider Computer 1 -RequireRow {
            CimCmdlets\Get-CimInstance Win32_ComputerSystemProduct -OperationTimeoutSec 3 -ErrorAction Stop |
                ForEach-Object { [ordered]@{ Hostname = [Environment]::MachineName; UUID = ConvertTo-HybridText $_.UUID 36 } }
        }
        Read-HybridProvider OS 1 -RequireRow {
            CimCmdlets\Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 3 -ErrorAction Stop |
                ForEach-Object { [ordered]@{
                    Caption = ConvertTo-HybridText $_.Caption; Version = ConvertTo-HybridText $_.Version 32
                    TotalMemoryKiB = [long]$_.TotalVisibleMemorySize; FreeMemoryKiB = [long]$_.FreePhysicalMemory
                } }
        }
        Read-HybridProvider NIC 16 -RequireRow {
            CimCmdlets\Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=True' -OperationTimeoutSec 3 -ErrorAction Stop |
                ForEach-Object { [ordered]@{
                    Description = ConvertTo-HybridText $_.Description; MACAddress = ConvertTo-HybridText $_.MACAddress 32
                    DHCPEnabled = [bool]$_.DHCPEnabled
                    IPAddress = @($_.IPAddress | Where-Object { $null -ne $_ } | Select-Object -First 8 | ForEach-Object { ConvertTo-HybridText $_ 64 })
                    Subnet = @($_.IPSubnet | Where-Object { $null -ne $_ } | Select-Object -First 8 | ForEach-Object { ConvertTo-HybridText $_ 64 })
                    Gateway = @($_.DefaultIPGateway | Where-Object { $null -ne $_ } | Select-Object -First 8 | ForEach-Object { ConvertTo-HybridText $_ 64 })
                    DNS = @($_.DNSServerSearchOrder | Where-Object { $null -ne $_ } | Select-Object -First 8 | ForEach-Object { ConvertTo-HybridText $_ 64 })
                } }
        }
        Read-HybridProvider Disk 16 -RequireRow {
            CimCmdlets\Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec 3 -ErrorAction Stop |
                ForEach-Object { [ordered]@{
                    Device = ConvertTo-HybridText $_.DeviceID 16; SizeBytes = [long]$_.Size; FreeBytes = [long]$_.FreeSpace
                } }
        }
        Read-HybridProvider CPU 8 -RequireRow {
            CimCmdlets\Get-CimInstance Win32_Processor -OperationTimeoutSec 3 -ErrorAction Stop |
                ForEach-Object { [ordered]@{
                    Name = ConvertTo-HybridText $_.Name; LogicalProcessors = [int]$_.NumberOfLogicalProcessors
                    LoadPercent = $(if ($null -eq $_.LoadPercentage) { $null } else { [int]$_.LoadPercentage })
                } }
        }
    )
    Complete-HybridRead $r
}

function Get-HybridServerServiceState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][guid]$CorrelationId, [Parameter(Mandatory)][ValidateSet('Spooler')][string]$Service)
    $ErrorActionPreference = 'Stop'
    $r = New-HybridContext $CorrelationId 'service'
    $r.Providers = @(Read-HybridProvider Service 1 -RequireRow {
        # Open only this service rather than enumerating the SCM service database.
        $controller = [System.ServiceProcess.ServiceController]::new('Spooler')
        try { [ordered]@{ Name = 'Spooler'; State = [string]$controller.Status } }
        finally { $controller.Dispose() }
    })
    Complete-HybridRead $r
}

function Get-HybridServerEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$CorrelationId,
        [Parameter(Mandatory)][ValidateSet('System','Application')][string]$Log,
        [Parameter(Mandatory)][ValidateRange(1,50)][int]$MaxCount,
        [Parameter(Mandatory)][ValidateRange(1,1440)][int]$LookbackMinutes
    )
    $ErrorActionPreference = 'Stop'
    $r = New-HybridContext $CorrelationId 'events'
    $r.Providers = @(Read-HybridProvider Events $MaxCount {
        try {
            $events = @(Microsoft.PowerShell.Diagnostics\Get-WinEvent -FilterHashtable @{
                LogName = $Log; StartTime = [DateTime]::UtcNow.AddMinutes(-$LookbackMinutes); EndTime = [DateTime]::UtcNow
            } -MaxEvents ($MaxCount + 1) -ErrorAction Stop)
        } catch {
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound,*') { return }
            throw
        }
        foreach ($event in $events) {
            [ordered]@{
                Log = $Log; RecordId = [long]$event.RecordId; Id = [int]$event.Id
                TimeCreatedUtc = $event.TimeCreated.ToUniversalTime().ToString('o')
                Level = ConvertTo-HybridText $event.LevelDisplayName 32
                Provider = ConvertTo-HybridText $event.ProviderName
                Message = ConvertTo-HybridText $event.Message 1024
            }
        }
    })
    Complete-HybridRead $r
}
Export-ModuleMember -Function Get-HybridServerFacts,Get-HybridServerServiceState,Get-HybridServerEvents
