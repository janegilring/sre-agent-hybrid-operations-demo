#Requires -Version 5.1
$RecoveryEndpoint = 'HybridSpoolerRecovery'
$RecoveryGroup = 'HybridSpoolerOperators'
$RecoveryRoot = "$env:ProgramData\HybridSpoolerRecovery"
$RecoveryModule = "$env:ProgramFiles\WindowsPowerShell\Modules\HybridSpoolerRecovery"
function Get-TextHash([string]$Text) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','') }
    finally { $hash.Dispose() }
}
function Invoke-SpoolerSc([ValidateSet('sdshow','sdset')][string]$Operation, [string]$Sddl) {
    $arguments = @($Operation,'Spooler')
    if ($Operation -eq 'sdset') {
        if (!$Sddl -or $Sddl -match '[\r\n"]') { throw 'Invalid SDDL argument.' }
        $arguments += $Sddl
    }
    $output = & "$env:SystemRoot\System32\sc.exe" @arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sc.exe $Operation failed ($LASTEXITCODE): $output" }
    if ($Operation -eq 'sdshow') {
        $lines = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^D:' })
        if ($lines.Count -ne 1) { throw 'sc.exe did not return exactly one DACL.' }
        ([Security.AccessControl.RawSecurityDescriptor]::new($lines[0])).GetSddlForm('Access')
    }
}
function Edit-SpoolerDacl([string]$Sddl, [string]$Sid, [switch]$Remove) {
    $sd = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    if ($null -eq $sd.DiscretionaryAcl) { throw 'Null service DACL refused.' }
    $identity = [Security.Principal.SecurityIdentifier]::new($Sid)
    $owned = [Security.AccessControl.CommonAce]::new('None','AccessAllowed',0x15,$identity,$false,$null)
    $matches = @()
    for ($i = 0; $i -lt $sd.DiscretionaryAcl.Count; $i++) {
        $ace = $sd.DiscretionaryAcl[$i]
        if ($ace -is [Security.AccessControl.KnownAce] -and $ace.SecurityIdentifier -eq $identity) { $matches += $i }
    }
    if ($Remove) {
        if ($matches.Count -ne 1 -or !$sd.DiscretionaryAcl[$matches[0]].Equals($owned)) { throw 'Owned ACE mismatch.' }
        $sd.DiscretionaryAcl.RemoveAce($matches[0])
    } else {
        if ($matches.Count) { throw 'Existing group ACE refused.' }
        $index = 0
        while ($index -lt $sd.DiscretionaryAcl.Count -and !$sd.DiscretionaryAcl[$index].IsInherited) { $index++ }
        $sd.DiscretionaryAcl.InsertAce($index,$owned)
    }
    $sd.GetSddlForm('Access')
}
function Set-SpoolerDaclChecked([string]$Before, [string]$After) {
    if ((Invoke-SpoolerSc sdshow) -cne $Before) { throw 'Concurrent service DACL change; no write.' }
    Invoke-SpoolerSc sdset $After
    if ((Invoke-SpoolerSc sdshow) -cne $After) { throw 'Service DACL postcondition failed; preserve receipt and investigate.' }
}
function Assert-RecoveryFile([string]$Path, [string]$Hash) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer) { throw 'Expected file.' }
    for ($node = $item; $null -ne $node; $node = $node.Parent) {
        if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point refused.' }
        if ($node -is [IO.FileInfo]) { $node = $node.Directory; if ($node.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point refused.' } }
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -cne $Hash) { throw "File ownership mismatch: $Path" }
}
function Get-RecoveryRegistration($Endpoint, [string]$Hash, [string]$Guid) {
    if (!$Endpoint -or $Endpoint.Name -cne $RecoveryEndpoint -or
        ![IO.Path]::IsPathRooted($Endpoint.ConfigFilePath)) { throw 'Invalid endpoint registration.' }
    Assert-RecoveryFile $Endpoint.ConfigFilePath $Hash
    if ([guid](Import-PowerShellDataFile $Endpoint.ConfigFilePath).Guid -ne [guid]$Guid) { throw 'Endpoint GUID mismatch.' }
    [pscustomobject]@{ Path = $Endpoint.ConfigFilePath; Hash = $Hash; Guid = $Guid }
}
