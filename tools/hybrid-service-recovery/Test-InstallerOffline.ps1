#Requires -Version 5.1
[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Ownership.ps1"
$scratch = Join-Path $PSScriptRoot ('.offline-' + [guid]::NewGuid().ToString())
$RecoveryRoot = "$scratch\receipt"
$RecoveryModule = "$scratch\module"
$null = New-Item $scratch -ItemType Directory
$script:Group = $null; $script:Endpoint = $null; $script:Writes = 0
$script:Dacl = 'D:(A;;CCLCSW;;;AU)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)'
$original = $script:Dacl
# All system mutation/query commands used by the scripts are shadowed here.
function Get-CimInstance { [pscustomobject]@{ DomainRole = 0 } }
function Get-LocalGroup { param($Name,$ErrorAction) $script:Group }
function New-LocalGroup {
    param($Name,$Description)
    $script:Group = [pscustomobject]@{ SID = [Security.Principal.SecurityIdentifier]::new('S-1-5-21-111-222-333-1001'); Description = $Description }
    $script:Group
}
function Get-LocalGroupMember { param($Name) }
function Remove-LocalGroup { param($SID) $script:Group = $null }
function Set-Acl { param($Path,$AclObject) }
function Get-PSSessionConfiguration { param($Name,$ErrorAction) $script:Endpoint }
function Register-PSSessionConfiguration {
    param($Name,$Path,$SecurityDescriptorSddl,[switch]$NoServiceRestart,[switch]$Force)
    if ($script:Endpoint) { throw 'Duplicate endpoint.' }
    Copy-Item $Path "$scratch\registered-copy.pssc"
    $script:Endpoint = [pscustomobject]@{ Name = $Name; ConfigFilePath = "$scratch\registered-copy.pssc" }
    $script:EndpointSddl = $SecurityDescriptorSddl
}
function Unregister-PSSessionConfiguration {
    param($Name,[switch]$NoServiceRestart,[switch]$Force)
    $script:Endpoint = $null
}
function Invoke-SpoolerSc {
    param($Operation,$Sddl)
    if ($Operation -eq 'sdshow') { return $script:Dacl }
    $script:Writes++; $script:Dacl = $Sddl
}
function Get-OfflineScript([string]$Name) {
    $text = Get-Content "$PSScriptRoot\$Name" -Raw
    # Only host/platform/identity preflight and helper import are replaced.
    # Receipt, DACL, configuration generation and cleanup bodies run unchanged.
    $text = $text -replace '(?m)^#Requires.*$', ''
    $text = $text.Replace('. "$PSScriptRoot\Ownership.ps1"','# Offline helpers already loaded')
    $text = $text -replace '(?m)^if \(\$PSVersionTable.PSEdition.*$', '# Offline host-independent execution'
    $text = $text -replace '(?m)^    \$sid = \(\[Security.Principal.NTAccount\].*$', "    `$sid = 'S-1-5-21-111-222-333-1002'"
    $text = $text.Replace('$ErrorActionPreference = ''Stop''',
        ('$ErrorActionPreference = ''Stop''; $PSScriptRoot = ''' + $PSScriptRoot.Replace("'","''") + ''''))
    [scriptblock]::Create($text)
}
function Check($Condition,$Message) { if (!$Condition) { throw "FAIL: $Message" } }
function Refused([scriptblock]$Action,$Pattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_ }
    Check ($caught -and $caught.ToString() -match $Pattern) "expected refusal $Pattern"
}
try {
    $install = Get-OfflineScript Install-HybridSpoolerRecovery.ps1
    $remove = Get-OfflineScript Remove-HybridSpoolerRecovery.ps1
    & $install -CallerIdentity 'EXAMPLE\operator' -WhatIf
    Check (!$script:Group -and $script:Writes -eq 0 -and !(Test-Path $RecoveryRoot)) 'install WhatIf no mutations'
    $script:Endpoint = [pscustomobject]@{ Name = 'HybridSpoolerRecovery'; ConfigFilePath = 'foreign' }
    Refused { & $install -CallerIdentity 'EXAMPLE\operator' -Confirm:$false } 'collision'
    Check (!$script:Group -and $script:Writes -eq 0) 'foreign endpoint preserved'
    $script:Endpoint = $null
    $null = & $install -CallerIdentity 'EXAMPLE\operator' -Confirm:$false
    $receipt = Get-Content "$RecoveryRoot\Ownership.json" -Raw | ConvertFrom-Json
    Check ($receipt.Phase -eq 'Registered' -and $receipt.Registration.Path -eq "$scratch\registered-copy.pssc") 'actual copied path receipt'
    Check ($script:EndpointSddl -notmatch ';;;WD|;;;AU|;;;BU' -and $script:EndpointSddl -match '1002') 'explicit caller-only endpoint ACL'
    Check ($receipt.Resource -eq 'Spooler' -and $receipt.Rights -eq 0x15 -and $script:Writes -eq 1) 'exact Spooler ACE installed'
    & $remove -WhatIf
    Check ($script:Endpoint -and $script:Group -and $script:Writes -eq 1) 'cleanup WhatIf preserves resources'
    $null = New-Item "$RecoveryRoot\foreign-empty" -ItemType Directory
    Refused { & $remove -Confirm:$false } 'Unexpected directories'
    Check (Test-Path "$RecoveryRoot\foreign-empty") 'foreign empty directory preserved'
    Remove-Item "$RecoveryRoot\foreign-empty"
    $owned = $script:Dacl
    $script:Dacl = $script:Dacl.Replace('CCLCSW','CCLC')
    Refused { & $remove -Confirm:$false } 'DACL drift'
    Check ($script:Endpoint -and $script:Writes -eq 1) 'foreign ACE drift blocks all removal'
    $script:Dacl = $owned
    Add-Content "$scratch\registered-copy.pssc" '# foreign modification'
    Refused { & $remove -Confirm:$false } 'ownership'
    Check ($script:Endpoint -and $script:Writes -eq 1) 'copied-path tamper blocks cleanup'
    Copy-Item "$RecoveryRoot\Endpoint.pssc" "$scratch\registered-copy.pssc" -Force
    $null = & $remove -Confirm:$false
    Check (!$script:Endpoint -and !$script:Group -and $script:Dacl -ceq $original -and
        !(Test-Path $RecoveryRoot) -and !(Test-Path $RecoveryModule)) 'owned cleanup preserves foreign service ACEs'
    "PASS: stubbed installer and cleanup lifecycle on PowerShell $($PSVersionTable.PSVersion); no system changes."
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
