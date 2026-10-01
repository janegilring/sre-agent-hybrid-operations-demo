#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$scratch = Join-Path $PSScriptRoot ('.ownership-offline-' + [guid]::NewGuid().ToString('N'))
$null = New-Item $scratch -ItemType Directory

# Run the production scripts with only host-specific paths, elevation/edition and
# account translation substituted. All registration/group/ACL commands are fakes.
function Get-TestScript {
    param([string]$Name)
    $text = Get-Content (Join-Path $PSScriptRoot $Name) -Raw
    $text = $text -replace '(?m)^#Requires -RunAsAdministrator\r?\n', ''
    $text = $text -replace '(?m)^if \(\$PSVersionTable.PSEdition.*\r?\n', ''
    $text = $text.Replace('C:\ProgramData\HybridServerReadOnly', "$script:caseRoot\Owned")
    $text = $text.Replace('C:\Program Files\WindowsPowerShell\Modules\HybridServerReadOnly', "$script:caseRoot\Module")
    $text = $text.Replace('$PSScriptRoot', $PSScriptRoot)
    $text = $text.Replace('([Security.Principal.NTAccount]::new($CallerIdentity)).Translate([Security.Principal.SecurityIdentifier])',
        "[Security.Principal.SecurityIdentifier]::new('S-1-5-21-111-222-333-1001')")
    [scriptblock]::Create($text)
}
function Get-CimInstance { param($ClassName) [pscustomobject]@{ DomainRole = 1 } }
function Get-LocalGroup { param($Name) $script:runtime }
function New-LocalGroup {
    param($Name,$Description)
    $script:runtime = [pscustomobject]@{ Name = $Name; Description = $Description
        SID = [Security.Principal.SecurityIdentifier]::new('S-1-5-21-111-222-333-1002') }
    $script:runtime
}
function Set-Acl { param($Path,$AclObject) }
function Get-LocalGroupMember { param($Group) $script:members }
function Remove-LocalGroup { param($Name) $script:runtime = $null; $script:groupRemovals++ }
function Get-PSSessionConfiguration { param($Name) $script:registration }
function Register-PSSessionConfiguration {
    param($Name,$Path,[switch]$NoServiceRestart,[switch]$Force)
    if (!$NoServiceRestart) { throw 'Restart not suppressed.' }
    $script:registerCalls++
    if ($script:mode -eq 'BeforeFailure') { throw 'Simulated registration failure before creation.' }
    $copy = "$script:caseRoot\SessionConfig\copied.pssc"
    $null = New-Item "$script:caseRoot\SessionConfig" -ItemType Directory
    Copy-Item -LiteralPath $Path -Destination $copy
    $script:registration = [pscustomobject]@{ Name = $Name; ConfigFilePath = $copy }
    if ($script:mode -eq 'AfterFailure') { throw 'Simulated registration failure after creation.' }
    if ($script:mode -eq 'BadCopy') { Add-Content $copy '# changed during registration' }
}
function Unregister-PSSessionConfiguration {
    param($Name,[switch]$NoServiceRestart,[switch]$Force)
    if (!$NoServiceRestart -or $Name -ne 'HybridServer.ReadOnly') { throw 'Unsafe unregister.' }
    $script:unregisterCalls++
    Remove-Item -LiteralPath $script:registration.ConfigFilePath
    $script:registration = $null
}
function New-PSSessionConfigurationFile {
    param($Path,$Guid,$Author,$SessionType,$LanguageMode,[switch]$RunAsVirtualAccount,
        $RunAsVirtualAccountGroups,$RoleDefinitions,$ModulesToImport,$ScriptsToProcess,
        $VisibleAliases,$VisibleCmdlets,$VisibleFunctions,$VisibleExternalCommands,$VisibleProviders)
    $caller = @($RoleDefinitions.Keys)[0]
    $role = $RoleDefinitions[$caller].RoleCapabilityFiles
    @"
@{
Guid = '$Guid'
SessionType = '$SessionType'
LanguageMode = '$LanguageMode'
RunAsVirtualAccount = `$$($RunAsVirtualAccount.IsPresent.ToString().ToLowerInvariant())
RunAsVirtualAccountGroups = '$RunAsVirtualAccountGroups'
ModulesToImport = '$ModulesToImport'
ScriptsToProcess = '$ScriptsToProcess'
RoleDefinitions = @{ '$caller' = @{ RoleCapabilityFiles = '$role' } }
VisibleAliases = @()
VisibleCmdlets = @()
VisibleFunctions = @()
VisibleExternalCommands = @()
VisibleProviders = @()
}
"@ | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Test-PSSessionConfigurationFile { param($Path) $true }
function Assert-Test { param($Condition,[string]$Message) if (!$Condition) { throw $Message } }
function Read-Receipt { Get-Content "$script:caseRoot\Owned\Ownership.json" -Raw | ConvertFrom-Json }
function Write-Receipt { param($Receipt) $Receipt | ConvertTo-Json -Depth 8 | Set-Content "$script:caseRoot\Owned\Ownership.json" -Encoding UTF8 }
function Invoke-Removal { & (Get-TestScript 'Remove-HybridServerReadOnly.ps1') -Confirm:$false }
function Assert-Rejected {
    $rejected = $false
    try { Invoke-Removal } catch { $rejected = $true }
    Assert-Test $rejected 'Expected removal rejection.'
    Assert-Test ($script:unregisterCalls -eq 0 -and $script:groupRemovals -eq 0) 'Rejected removal mutated endpoint/group.'
    Assert-Test ((Test-Path "$script:caseRoot\Owned") -and (Test-Path "$script:caseRoot\Module")) 'Rejected removal deleted files.'
}
$cases = @('RoundTrip','PathTamper','HashTamper','ForeignGuid','ReceiptHash','ReceiptPath','ReceiptGuid','EndpointName',
    'SetupTamper','NonadminTamper','ForeignFile','ForeignDirectory','GroupMember','GroupSid',
    'BeforeFailure','AfterFailure','BadCopy','WhatIf','InstallWhatIf','GroupCollision','EndpointCollision')
try {
    foreach ($case in $cases) {
        $script:caseRoot = Join-Path $scratch $case
        $null = New-Item $script:caseRoot -ItemType Directory
        $script:runtime = $null; $script:registration = $null; $script:members = @()
        $script:registerCalls = 0; $script:unregisterCalls = 0; $script:groupRemovals = 0
        $script:mode = $case
        if ($case -in @('InstallWhatIf','GroupCollision','EndpointCollision')) {
            if ($case -eq 'GroupCollision') { $script:runtime = [pscustomobject]@{ Description = 'foreign' } }
            if ($case -eq 'EndpointCollision') { $script:registration = [pscustomobject]@{ Name = 'HybridServer.ReadOnly'; ConfigFilePath = 'foreign' } }
            $rejected = $false
            try {
                & (Get-TestScript 'Install-HybridServerReadOnly.ps1') -CallerIdentity 'EXAMPLE\reader$' -Confirm:$false -WhatIf:($case -eq 'InstallWhatIf') | Out-Null
            } catch { $rejected = $true }
            Assert-Test ($case -eq 'InstallWhatIf' -or $rejected) 'Collision accepted.'
            Assert-Test ($script:registerCalls -eq 0 -and $script:unregisterCalls -eq 0 -and
                $script:groupRemovals -eq 0 -and !(Test-Path "$script:caseRoot\Owned")) 'Collision/WhatIf changed resources.'
            if ($case -eq 'GroupCollision') { Assert-Test ($script:runtime.Description -eq 'foreign') 'Foreign group changed.' }
            if ($case -eq 'EndpointCollision') { Assert-Test ($script:registration.ConfigFilePath -eq 'foreign') 'Foreign endpoint changed.' }
            "PASS ownership: $case"
            continue
        }
        $failed = $false
        try { & (Get-TestScript 'Install-HybridServerReadOnly.ps1') -CallerIdentity 'EXAMPLE\reader$' -Confirm:$false | Out-Null }
        catch { if ($case -notin @('BeforeFailure','AfterFailure','BadCopy')) { throw }; $failed = $true }
        $receipt = Read-Receipt
        if ($case -in @('BeforeFailure','AfterFailure','BadCopy')) {
            Assert-Test ($failed -and $receipt.RegistrationState -eq 'Pending' -and !$receipt.Registration) 'Failure claimed registered ownership.'
            if ($case -eq 'BeforeFailure') {
                Invoke-Removal | Out-Null
                Assert-Test ($script:unregisterCalls -eq 0 -and $script:groupRemovals -eq 1) 'Absent endpoint partial cleanup failed.'
            } else { Assert-Rejected }
        } else {
            Assert-Test ($receipt.RegistrationState -eq 'Registered') 'Registration receipt missing.'
            Assert-Test ($receipt.Registration.ConfigFilePath -eq $script:registration.ConfigFilePath -and
                $receipt.Registration.ConfigFilePath -ne "$script:caseRoot\Owned\Endpoint.pssc") 'Copied registered path not recorded.'
            switch ($case) {
                'RoundTrip' {
                    Invoke-Removal | Out-Null
                    Assert-Test ($script:unregisterCalls -eq 1 -and $script:groupRemovals -eq 1 -and
                        !(Test-Path "$script:caseRoot\Owned") -and !(Test-Path "$script:caseRoot\Module")) 'Round trip cleanup failed.'
                }
                'PathTamper' {
                    Copy-Item $script:registration.ConfigFilePath "$script:caseRoot\foreign.pssc"
                    $script:registration.ConfigFilePath = "$script:caseRoot\foreign.pssc"
                    Assert-Rejected
                }
                'HashTamper' { Add-Content $script:registration.ConfigFilePath '# foreign change'; Assert-Rejected }
                'ForeignGuid' {
                    $path = $script:registration.ConfigFilePath
                    (Get-Content $path -Raw).Replace($receipt.ConfigurationGuid, [guid]::NewGuid().ToString()) | Set-Content $path
                    Assert-Rejected
                }
                'ReceiptHash' { $receipt.Registration.Sha256 = 'invalid'; Write-Receipt $receipt; Assert-Rejected }
                'ReceiptPath' { $receipt.Registration.ConfigFilePath = "$script:caseRoot\foreign.pssc"; Write-Receipt $receipt; Assert-Rejected }
                'ReceiptGuid' { $receipt.ConfigurationGuid = [guid]::NewGuid().ToString(); Write-Receipt $receipt; Assert-Rejected }
                'EndpointName' { $script:registration.Name = 'Foreign.Endpoint'; Assert-Rejected }
                { $_ -in @('SetupTamper','NonadminTamper') } {
                    $source = "$script:caseRoot\Owned\Endpoint.pssc"
                    $text = Get-Content $source -Raw
                    if ($case -eq 'SetupTamper') { $text = $text.Replace("LanguageMode = 'NoLanguage'", "LanguageMode = 'FullLanguage'") }
                    else { $text = $text.Replace("RunAsVirtualAccountGroups = 'HybridServerReaders'", "RunAsVirtualAccountGroups = 'Administrators'") }
                    $text | Set-Content $source
                    Copy-Item $source $script:registration.ConfigFilePath -Force
                    $hash = (Get-FileHash $source).Hash
                    $receipt.Files.PSObject.Properties[$source].Value = $hash
                    $receipt.Registration.Sha256 = $hash
                    Write-Receipt $receipt
                    Assert-Rejected
                }
                'ForeignFile' { Set-Content "$script:caseRoot\Owned\foreign.txt" 'preserve'; Assert-Rejected }
                'ForeignDirectory' { $null = New-Item "$script:caseRoot\Owned\foreign" -ItemType Directory; Assert-Rejected }
                'GroupMember' { $script:members = @('foreign'); Assert-Rejected }
                'GroupSid' { $script:runtime.SID = [Security.Principal.SecurityIdentifier]::new('S-1-5-21-111-222-333-9999'); Assert-Rejected }
                'WhatIf' {
                    & (Get-TestScript 'Remove-HybridServerReadOnly.ps1') -WhatIf
                    Assert-Test ($script:unregisterCalls -eq 0 -and $script:groupRemovals -eq 0 -and (Test-Path "$script:caseRoot\Owned")) 'WhatIf mutated state.'
                }
            }
        }
        "PASS ownership: $case"
    }
} finally { Remove-Item -LiteralPath $scratch -Recurse -Force }
"PASS: $($cases.Count) ownership cases on PowerShell $($PSVersionTable.PSVersion); fake registration/group/ACL commands only."
