#Requires -Version 5.1
[CmdletBinding()]
param([string]$PublishDirectory)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Assert-Contract {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}
function Read-KitFile {
    param([string]$Path)
    Get-Content -LiteralPath (Join-Path $root $Path) -Raw
}
function Assert-Skill {
    param([string]$Text)
    $normalized = $Text.Replace("`r`n", "`n")
    $frontMatter = [regex]::Match($normalized, '\A---\n(.*?)\n---\n', 'Singleline')
    Assert-Contract $frontMatter.Success 'Missing skill front matter.'
    $lines = $frontMatter.Groups[1].Value.Split("`n")
    Assert-Contract ($lines.Count -eq 2) 'Only name and description are allowed; no tool attachments.'
    Assert-Contract ($lines[0] -ceq 'name: azure-local-operations-triage') 'Unexpected skill name.'
    Assert-Contract ($lines[1] -cmatch '^description: Read-only, evidence-led triage for Azure Local ') 'Unexpected skill description.'
    foreach ($heading in @('When to use', 'Boundaries', 'Procedure', 'Expected output', 'Official reference starting points')) {
        Assert-Contract ($normalized.Contains("## $heading`n")) "Missing skill section: $heading"
    }
    foreach ($state in @('DENIED', 'UNSUPPORTED', 'TIMEDOUT', 'PARTIAL', 'UNKNOWN')) {
        Assert-Contract ($normalized.Contains($state)) "Missing evidence state: $state"
    }
    Assert-Contract ($normalized.Contains('are always APPROVAL-REQUIRED OPERATION, never APPROVED READ.')) 'Readiness-rerun approval gate changed.'
    Assert-Contract ($normalized.Contains('In a supplied-evidence-only task, no new infrastructure read is authorized.')) 'Supplied-evidence scope changed.'
    foreach ($link in [regex]::Matches($normalized, 'https?://[^\s)]+')) {
        Assert-Contract ($link.Value.StartsWith('https://learn.microsoft.com/')) 'Unofficial skill reference.'
    }
}

$documents = @(
    'docs\guest-setup.md',
    'docs\mcp-service-install.md',
    'docs\attendee-readiness.md',
    'docs\custom-skill.md',
    'docs\native-reports.md',
    'tools\private-mcp\README.md',
    'tools\hybrid-server\README.md'
)
$blockCount = 0
foreach ($document in $documents) {
    $text = Read-KitFile $document
    foreach ($match in [regex]::Matches($text, '(?ms)^```powershell\r?\n(.*?)^```[ \t]*\r?$')) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput(
            $match.Groups[1].Value, [ref]$tokens, [ref]$parseErrors)
        Assert-Contract ($parseErrors.Count -eq 0) "Invalid PowerShell in $document block $blockCount`: $parseErrors"
        $blockCount++
    }
}
Assert-Contract ($blockCount -ge 15) 'Expected attendee command blocks were not found.'

$install = Read-KitFile 'docs\mcp-service-install.md'
$guest = Read-KitFile 'docs\guest-setup.md'
$program = Read-KitFile 'tools\private-mcp\src\Program.cs'
$settings = Read-KitFile 'tools\private-mcp\src\BoundarySettings.cs'
$reader = Read-KitFile 'tools\private-mcp\src\ServerReader.cs'
$project = [xml](Read-KitFile 'tools\private-mcp\src\PrivateMcp.csproj')
Assert-Contract ($project.Project.PropertyGroup.TargetFramework -eq 'net10.0') 'Update the documented runtime.'
Assert-Contract ($project.Project.PropertyGroup.RuntimeIdentifiers -eq 'win-x64') 'Update the documented architecture.'
foreach ($required in @('--runtime win-x64 --self-contained false', '--no-restore --output tools\private-mcp\src\bin\publish\win-x64',
    "`$binaryPath = '""' + `$exePath + '""'", "`$PSNativeCommandArgumentPassing = 'Standard'",
    'binPath= $binaryPath start= demand obj= $account')) {
    Assert-Contract ($install.Contains($required)) "Missing installation contract: $required"
}
Assert-Contract ($program.Contains('options.ServiceName = "LocalBoxPrivateMcp"')) 'SCM name differs from documented registration.'
Assert-Contract ($program.Contains('Path.Combine(AppContext.BaseDirectory, "boundary.local.json")')) 'Configuration location changed.'
Assert-Contract ($settings.Contains('Port { get; init; } = 8443')) 'Listener port changed.'
Assert-Contract ($reader.Contains('http://{target.Hostname}:5985/wsman')) 'Guest transport changed.'
Assert-Contract ($reader.Contains('AuthenticationMechanism = AuthenticationMechanism.Kerberos')) 'Guest authentication changed.'
Assert-Contract ($guest.Contains('PrincipalsAllowedToRetrieveManagedPassword = $broker')) 'Password retrieval must be scoped to the broker.'
Assert-Contract ($guest.Contains('Test-ADServiceAccount')) 'Missing local gMSA acceptance.'
Assert-Contract (-not [regex]::IsMatch($guest, '(?m)^\s*Add-KdsRootKey.*AddHours')) 'Do not make KDS backdating a runnable default.'
foreach ($command in @('Install-HybridServerReadOnly', 'Test-HybridServerReadOnly', 'Remove-HybridServerReadOnly')) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root "tools\hybrid-server\$command.ps1"), [ref]$tokens, [ref]$parseErrors)
    Assert-Contract ($parseErrors.Count -eq 0) "Invalid source script: $command"
    $parameters = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
    $required = switch ($command) {
        'Install-HybridServerReadOnly' { @('CallerIdentity') }
        'Test-HybridServerReadOnly' { @('ComputerName', 'ExpectedMachine', 'ExpectedCaller') }
        'Remove-HybridServerReadOnly' { @() }
    }
    foreach ($parameter in $required) {
        Assert-Contract ($parameters -contains $parameter) "Documented parameter is missing: $command/$parameter"
    }
}

$skill = Read-KitFile 'skills\azure-local-operations-triage\SKILL.md'
Assert-Skill $skill
$mutations = @(
    $skill.Replace('name: azure-local-operations-triage', 'name: unrelated'),
    $skill.Replace('description:', "tools: [unapproved-tool]`ndescription:"),
    $skill.Replace('DENIED', 'OK'),
    $skill.Replace('are always APPROVAL-REQUIRED OPERATION, never APPROVED READ.', 'are always APPROVED READ.'),
    $skill.Replace('https://learn.microsoft.com/', 'https://example.test/')
)
foreach ($mutation in $mutations) {
    $rejected = $false
    try { Assert-Skill $mutation } catch { $rejected = $true }
    Assert-Contract $rejected 'A negative skill mutation was not rejected.'
}

if ($PublishDirectory) {
    $published = (Resolve-Path -LiteralPath $PublishDirectory).Path
    foreach ($name in @('PrivateMcp.exe', 'PrivateMcp.dll', 'PrivateMcp.deps.json',
        'PrivateMcp.runtimeconfig.json', 'System.Management.Automation.dll', 'ModelContextProtocol.dll')) {
        Assert-Contract (Test-Path -LiteralPath (Join-Path $published $name) -PathType Leaf) "Missing publish artifact: $name"
    }
    $runtime = Get-Content -LiteralPath (Join-Path $published 'PrivateMcp.runtimeconfig.json') -Raw | ConvertFrom-Json
    foreach ($name in @('Microsoft.NETCore.App', 'Microsoft.AspNetCore.App')) {
        $framework = @($runtime.runtimeOptions.frameworks | Where-Object { $_.name -eq $name })
        Assert-Contract ($framework.Count -eq 1 -and $framework[0].version -like '10.0.*') "Unexpected shared framework: $name"
    }
    Assert-Contract (-not (Test-Path -LiteralPath (Join-Path $published 'boundary.local.json'))) 'Private config must not be in build artifacts.'
    $exe = [System.IO.File]::ReadAllBytes((Join-Path $published 'PrivateMcp.exe'))
    $peOffset = [BitConverter]::ToInt32($exe, 0x3c)
    Assert-Contract ([BitConverter]::ToUInt16($exe, $peOffset + 4) -eq 0x8664) 'Published executable is not Windows x64.'
    Write-Output 'PASS: framework-dependent Windows x64 publish shape and .NET/ASP.NET Core 10 requirements.'
}
Write-Output "PASS: $blockCount PowerShell doc blocks parsed on $($PSVersionTable.PSVersion); source contracts; skill and five negative mutations."
Write-Output 'No documentation command executed; no AD, SCM, certificate, guest, Azure or native-agent acceptance implied.'
