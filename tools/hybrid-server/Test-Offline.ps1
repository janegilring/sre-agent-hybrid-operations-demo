[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$failures = @()
Get-ChildItem $PSScriptRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1','.psd1','.psrc' } | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { $failures += $errors }
}
if ($failures.Count) { throw ($failures -join "`n") }
$manifest = Test-ModuleManifest "$PSScriptRoot\HybridServerReadOnly\HybridServerReadOnly.psd1"
if ($manifest.ExportedFunctions.Count -ne 3) { throw 'Unexpected exported capability.' }
$module = Import-Module "$PSScriptRoot\HybridServerReadOnly\HybridServerReadOnly.psd1" -Force -PassThru
& $module {
    $r = Read-HybridProvider Test 2 { 1; 2; 3 }
    if ($r.Status -ne 'partial' -or !$r.Truncated -or $r.Rows.Count -ne 2) { throw 'Bounded provider test failed.' }
    $r = Read-HybridProvider Test 2 { throw 'private details' }
    if ($r.Status -ne 'unknown' -or $r.Rows.Count -ne 0 -or ($r | ConvertTo-Json) -match 'private details') { throw 'Failure privacy test failed.' }
    $r = Read-HybridProvider Test 1 -RequireRow {}
    if ($r.Status -ne 'unknown') { throw 'Empty observation test failed.' }
    $r = Read-HybridProvider Test 1 { throw [ComponentModel.Win32Exception]::new(5) }
    if ($r.Status -ne 'denied' -or $r.ErrorCode -ne 'ProviderAccessDenied' -or $r.Rows.Count) { throw 'Access denied test failed.' }
    if ((ConvertTo-HybridText ("x" * 2000) 1024).Length -ne 1024) { throw 'Text bound failed.' }
}
foreach ($probe in @(
    { Get-HybridServerServiceState -CorrelationId ([guid]::NewGuid()) -Service WinRM },
    { Get-HybridServerEvents -CorrelationId ([guid]::NewGuid()) -Log Security -MaxCount 1 -LookbackMinutes 1 },
    { Get-HybridServerEvents -CorrelationId ([guid]::NewGuid()) -Log System -MaxCount 51 -LookbackMinutes 1 },
    { Get-HybridServerEvents -CorrelationId ([guid]::NewGuid()) -Log System -MaxCount 1 -LookbackMinutes 1441 },
    { Get-HybridServerFacts -CorrelationId ([guid]::NewGuid()) -ComputerName other }
)) {
    $denied = $false
    try { & $probe } catch [Management.Automation.ParameterBindingException] { $denied = $true }
    if (!$denied) { throw 'Offline parameter denial failed.' }
}
Remove-Module $module
& "$PSScriptRoot\Test-OwnershipOffline.ps1"
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    # Scratch stays inside this checked-out project, is never registered, and is removed on completion.
    $scratch = Join-Path $PSScriptRoot ('.offline-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item $scratch -ItemType Directory
    try {
        '$global:HybridServerConnectingIdentity = [string]$PSSenderInfo.UserInfo.Identity.Name' |
            Set-Content "$scratch\Initialize.ps1"
        & "$PSScriptRoot\New-HybridServerConfiguration.ps1" -Path "$scratch\Endpoint.pssc" `
            -CallerIdentity 'EXAMPLE\mcpRead$' -ModulePath "$PSScriptRoot\HybridServerReadOnly" `
            -InitializePath "$scratch\Initialize.ps1"
        $config = Import-PowerShellDataFile "$scratch\Endpoint.pssc"
        if ($config.LanguageMode -ne 'NoLanguage' -or !$config.RunAsVirtualAccount -or
            $config.RunAsVirtualAccountGroups -ne 'HybridServerReaders' -or
            $config.RoleDefinitions.Count -ne 1 -or !$config.RoleDefinitions.ContainsKey('EXAMPLE\mcpRead$')) {
            throw 'Generated JEA mapping/identity failed.'
        }
        foreach ($name in 'VisibleAliases','VisibleCmdlets','VisibleFunctions','VisibleExternalCommands','VisibleProviders') {
            if ($null -ne $config[$name] -and @($config[$name]).Count) { throw "Global command/provider visibility found: $name" }
        }
        . "$PSScriptRoot\Ownership.ps1"
        $source = "$scratch\Endpoint.pssc"
        $sourceHash = (Get-FileHash $source -Algorithm SHA256).Hash
        $receipt = @{ SchemaVersion = 2; EndpointName = 'HybridServer.ReadOnly'; RegistrationState = 'Pending'
            CallerIdentity = 'EXAMPLE\mcpRead$'; CallerSid = 'S-1-5-21-111-222-333-1001'
            ConfigurationGuid = [string]$config.Guid; Files = @{ $source = $sourceHash } } |
            ConvertTo-Json -Depth 5 | ConvertFrom-Json
        if ((Assert-HybridOwnedConfiguration $receipt $scratch "$PSScriptRoot\HybridServerReadOnly") -ne $sourceHash) {
            throw 'Native Windows 5.1 configuration ownership validation failed.'
        }
    } finally { Remove-Item $scratch -Recurse }
}
'PASS: parsing, manifest, bounded provider execution, privacy, empty observations and parameter-denial tests; Windows 5.1 also generates/validates secure PSSC. Guest JEA tests pending.'
