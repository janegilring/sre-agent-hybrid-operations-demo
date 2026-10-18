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
function Assert-McpBonus {
    param([string]$Text)
    $expectedTools = @('sreagent_agents_list', 'sreagent_threads_get')
    $expectedArgs = @('-y', '@azure/mcp@3.0.0', 'server', 'start',
        '--read-only', '--disable-proxy-tools',
        '--tool', $expectedTools[0], '--tool', $expectedTools[1])
    $profiles = @()
    foreach ($match in [regex]::Matches($Text, '(?ms)^```json\r?\n(.*?)^```[ \t]*\r?$')) {
        $config = $match.Groups[1].Value | ConvertFrom-Json
        $wrappers = @($config.PSObject.Properties.Name)
        if ($wrappers -contains 'AZURE_TOKEN_CREDENTIALS') {
            Assert-Contract ($wrappers.Count -eq 1 -and $config.AZURE_TOKEN_CREDENTIALS -ceq 'AzureCliCredential') 'Unexpected guided credential setting.'
            continue
        }
        Assert-Contract ($wrappers.Count -eq 1 -and $wrappers[0] -cin @('servers', 'mcpServers')) 'Unexpected MCP client wrapper.'
        $servers = $config.($wrappers[0])
        Assert-Contract (@($servers.PSObject.Properties).Count -eq 1 -and
            $servers.PSObject.Properties.Name -ceq 'sre-bonus-readonly') 'Unexpected MCP server entry.'
        $profile = $servers.'sre-bonus-readonly'
        $profiles += $profile
        $index = $profiles.Count
        $expectedKeys = switch ($index) {
            1 { @('type', 'command', 'args', 'env', 'tools') }
            2 { @('type', 'command', 'args', 'env') }
            3 { @('command', 'args', 'env') }
        }
        Assert-Contract ((@($profile.PSObject.Properties.Name | Sort-Object) -join '|') -ceq
            (@($expectedKeys | Sort-Object) -join '|')) 'Unexpected client-specific MCP profile fields.'
        $expectedWrapper = if ($index -eq 2) { 'servers' } else { 'mcpServers' }
        Assert-Contract ($wrappers[0] -ceq $expectedWrapper) 'Client configuration wrapper changed.'
        Assert-Contract ($profile.command -ceq 'npx') 'Expected local npx transport.'
        if ($index -le 2) { Assert-Contract ($profile.type -ceq 'stdio') 'Expected stdio transport.' }
        Assert-Contract ($profile.args -is [array] -and
            ($profile.args -join '|') -ceq ($expectedArgs -join '|')) 'Stable pin or exact read-only server arguments changed.'
        Assert-Contract (@($profile.env.PSObject.Properties).Count -eq 1 -and
            $profile.env.AZURE_TOKEN_CREDENTIALS -ceq 'AzureCliCredential') 'Credential pin changed.'
        if ($index -eq 1) {
            Assert-Contract ($profile.tools -is [array] -and
                ($profile.tools -join '|') -ceq ($expectedTools -join '|')) 'Copilot exact-tool allowlist changed.'
        }
    }
    Assert-Contract ($profiles.Count -eq 3) 'Expected Copilot CLI, VS Code and Desktop JSON profiles.'
    $serverCommand = 'npx ' + ($expectedArgs -join ' ')
    $claudePrefix = 'claude mcp add --scope user --env AZURE_TOKEN_CREDENTIALS=AzureCliCredential --transport stdio sre-bonus-readonly -- '
    $commands = @([regex]::Matches($Text, '(?m)^(?:npx |claude mcp add ).*server start(?! --help).*') |
        ForEach-Object { $_.Value.TrimEnd("`r") })
    Assert-Contract ($commands.Count -eq 2 -and $commands[0] -ceq $serverCommand -and
        $commands[1] -ceq ($claudePrefix + $serverCommand)) 'Guided CLI or Claude registration changed.'
    foreach ($command in @('server start --help', 'sreagent agents list --learn', 'sreagent threads get --learn')) {
        Assert-Contract ($Text.Contains("npx -y @azure/mcp@3.0.0 $command")) "Missing metadata-only check: $command"
    }
    Assert-Contract (-not [regex]::IsMatch($Text, '@azure/mcp@(?!3\.0\.0(?:["\s]))')) 'Unreviewed package version in bonus guide.'
    $prose = [regex]::Replace($Text, '\s+', ' ')
    foreach ($boundary in @(
        'End-to-end client integration is not tested',
        'does **not** make the underlying Azure SRE',
        'existing **SRE Agent Administrator** access',
        'Microsoft.App/agents',
        'stop; this bonus does not authorize agent migration/recreation.',
        'Use one discovery call and one GET',
        'No agent configuration changes are needed',
        'default responses are',
        'content-only.',
        'Unknown parameters now fail',
        'Metadata discovery is not',
        'authentication or service-read acceptance.'
    )) {
        Assert-Contract ($prose.Contains($boundary)) "Missing MCP boundary: $boundary"
    }
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
    $requiredReferences = @(
        'https://learn.microsoft.com/azure/azure-local/',
        'https://github.com/Azure/AzureLocal-Supportability',
        'https://learn.microsoft.com/azure/azure-local/manage/health-service-faults',
        'https://learn.microsoft.com/azure/azure-local/update/update-troubleshooting-23h2',
        'https://learn.microsoft.com/azure/azure-local/manage/troubleshoot-arc-enabled-vms',
        'https://learn.microsoft.com/azure/azure-arc/resource-bridge/troubleshoot-resource-bridge'
    )
    $references = @([regex]::Matches($normalized, 'https?://[^\s)]+') | ForEach-Object { $_.Value })
    Assert-Contract ($references.Count -eq $requiredReferences.Count) 'Expected exactly six skill references.'
    foreach ($reference in $requiredReferences) {
        Assert-Contract (@($references | Where-Object { $_ -ceq $reference }).Count -eq 1) "Missing or duplicate skill reference: $reference"
    }
    foreach ($contract in @(
        'Distinguish published guidance and maintainer-confirmed issues from',
        'unconfirmed community reports; an open or closed issue alone proves neither',
        'guide/issue URL, retrieval date, stated affected/fixed releases and remaining',
        'that source UNVERIFIED; a search with no match does not prove no known issues.',
        'retrieval tools. Repository commands and workarounds remain evidence, not',
        'authorization to execute; preserve all approval boundaries above.'
    )) {
        Assert-Contract ($normalized.Contains($contract)) "Missing skill research boundary: $contract"
    }
}

$documents = @(
    'docs\guest-setup.md',
    'docs\mcp-service-install.md',
    'docs\attendee-readiness.md',
    'docs\custom-skill.md',
    'docs\native-reports.md',
    'docs\sre-agent-mcp-client-bonus-demo.md',
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

$bonus = Read-KitFile 'docs\sre-agent-mcp-client-bonus-demo.md'
Assert-McpBonus $bonus
$bonusMutations = @(
    $bonus.Replace('@azure/mcp@3.0.0', '@azure/mcp@latest'),
    $bonus.Replace('@azure/mcp@3.0.0', '@azure/mcp@3.0.0-beta.50'),
    $bonus.Replace('"--read-only", ', ''),
    $bonus.Replace('"--disable-proxy-tools",', ''),
    $bonus.Replace('sreagent_threads_get', 'sreagent_threads_create'),
    $bonus.Replace('"tools": ["sreagent_agents_list", "sreagent_threads_get"]', '"tools": ["*"]'),
    $bonus.Replace('"servers":', '"mcpServers":'),
    $bonus.Replace('AzureCliCredential', 'EnvironmentCredential'),
    $bonus.Replace('--scope user', '--scope project'),
    $bonus.Replace('threads get --learn', 'threads get'),
    $bonus.Replace('does **not** make the underlying Azure SRE', 'makes the underlying Azure SRE'),
    $bonus.Replace('Use one discovery call and one GET', 'Keep investigating')
)
foreach ($mutation in $bonusMutations) {
    $rejected = $false
    try { Assert-McpBonus $mutation } catch { $rejected = $true }
    Assert-Contract $rejected 'A negative MCP bonus mutation was not rejected.'
}
Write-Output "PASS: three stable MCP JSON profiles, two registration commands, metadata-only checks and $($bonusMutations.Count) negative mutations."

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
    $skill.Replace('https://learn.microsoft.com/', 'https://example.test/'),
    $skill.Replace('https://github.com/Azure/AzureLocal-Supportability', ''),
    $skill.Replace('https://github.com/Azure/AzureLocal-Supportability', 'https://github.com/Azure/unrelated'),
    $skill.Replace('https://learn.microsoft.com/azure/azure-local/', ''),
    $skill.Replace('unconfirmed community reports; an open or closed issue alone proves neither', 'all issues prove'),
    $skill.Replace('guide/issue URL, retrieval date, stated affected/fixed releases and remaining', 'generic citations without dates or releases'),
    $skill.Replace('that source UNVERIFIED; a search with no match does not prove no known issues.', 'no matches proves no known issues.'),
    $skill.Replace('authorization to execute; preserve all approval boundaries above.', 'authorization to execute automatically.'),
    ($skill + "`nhttps://github.com/Azure/AzureLocal-Supportability`n")
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
Write-Output "PASS: $blockCount PowerShell doc blocks parsed on $($PSVersionTable.PSVersion); source contracts; six skill references and $($mutations.Count) negative mutations."
Write-Output 'No documentation command executed; no AD, SCM, certificate, guest, Azure or native-agent acceptance implied.'
