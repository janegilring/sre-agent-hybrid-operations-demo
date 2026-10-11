#Requires -Version 7.5
[CmdletBinding()]
param([string]$Root = (Split-Path $PSScriptRoot))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Read-StrictJson.ps1"

function Get-TextHash([string]$Text) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
function Get-FileHashValue([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-PackageText([string]$Path) {
    # Invalid UTF-8 must not hide bindings behind replacement characters.
    $text=[Text.UTF8Encoding]::new($false,$true).GetString([IO.File]::ReadAllBytes($Path))
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xfeff) { $text=$text.Substring(1) }
    return $text
}
function Test-JsonTruthy($Value) {
    # Python JSON truthiness counts containers, rather than testing their members.
    # JSON keys such as Count must not shadow the dictionary's actual size.
    if ($Value -is [Collections.IDictionary]) { return $Value.psbase.Count -gt 0 }
    if ($Value -is [array]) { return $Value.Length -gt 0 }
    return [bool]$Value
}
function Test-JsonNumber($Value) {
    # Python accepts JSON booleans in numeric comparisons (true == 1).
    return ($Value -is [long] -or $Value -is [int] -or $Value -is [double] -or
        $Value -is [decimal] -or $Value -is [bigint] -or $Value -is [bool])
}
function Test-Package {
    param([string]$Root)
    $Root = [IO.Path]::GetFullPath($Root)
    $errors = [Collections.Generic.List[string]]::new()
    $gitOutput = & git -C $Root -c core.quotepath=false ls-files --cached --others --exclude-standard -z
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate package with Git' }
    $names = @((($gitOutput -join "`n") -split "`0") | Where-Object { $_ } | Sort-Object -Unique -CaseSensitive)
    $manifest = ConvertFrom-KitJson (Read-PackageText "$Root\packaging\source-manifest.json")
    $allowlist = ConvertFrom-KitJson (Read-PackageText "$Root\packaging\export-paths.json")
    if ($manifest -isnot [Collections.IDictionary] -or $manifest['files'] -isnot [array]) { throw 'Invalid source manifest: files must be a JSON array' }
    if ($allowlist -isnot [array]) { throw 'Invalid export allowlist: expected a JSON array' }
    foreach ($allowedPath in $allowlist) {
        if ($allowedPath -isnot [string]) { throw 'Invalid export allowlist path: expected a scalar string' }
    }
    foreach ($entry in $manifest.files) {
        if ($entry -isnot [Collections.IDictionary]) { throw 'Invalid source manifest entry: expected a JSON object' }
        foreach ($field in @('path','exportSha256','sourceSha256','originCommit','originRepository','originBlob')) {
            if ($entry[$field] -isnot [string]) { throw "Invalid manifest $field scalar string" }
        }
    }
    $manifestPaths = @($manifest.files | ForEach-Object { $_.path })
    if (($allowlist | Sort-Object -CaseSensitive | ConvertTo-Json -Compress) -cne ($manifestPaths | Sort-Object -CaseSensitive | ConvertTo-Json -Compress)) {
        $errors.Add('Source manifest differs from explicit export path allowlist')
    }
    if (@($manifestPaths | Sort-Object -Unique -CaseSensitive).Count -ne $manifestPaths.Count) { $errors.Add('Duplicate manifest path') }
    # Only these source-pinned, explicitly translated tooling artifacts may differ.
    $derivatives = @{
        'infra/hybrid-monitoring/tests/Test-Queries.ps1' = @('infra/hybrid-monitoring/tests/test_queries.py','03788334a7a2a97e5eae588a0609a978b7e3c943202b370c023a5fd8f66cbb32')
        'infra/hybrid-service-monitoring/tests/Test-Contract.ps1' = @('infra/hybrid-service-monitoring/tests/test_contract.py','7cfe438841e8c229eed51f1c0252db12ffdab3d411b31926663538ab9fb74a98')
        'infra/hybrid-arc-connectivity/Test-Connectivity.ps1' = @('infra/hybrid-arc-connectivity/test_connectivity.py','07c7ae1b4f0dde6583324b499671f53198964dda5038cb18fe6ba412b6943cf0')
        'infra/hybrid-arc-connectivity/Test-Inputs.ps1' = @('infra/hybrid-arc-connectivity/validate_inputs.py','aaae8bdd481cae2c7ee103eb9f2bd17b9d87b161ca39ef81518a6d79e2d9a32a')
        'infra/sre-agent-starter/Test-Regression.ps1' = @('infra/sre-agent-starter/Test-Regression.ps1','1efaed6479f36f5e592152fab136074ddf92af9fc84b246bc183b68b8c47f303')
    }
    $monitoringRefresh = @('infra/hybrid-monitoring/Common.ps1','infra/hybrid-monitoring/main.bicep','infra/hybrid-monitoring/README.md','infra/hybrid-monitoring/tests/Test-Scripts.ps1','infra/hybrid-monitoring/tests/Test-Template.ps1')
    foreach ($entry in $manifest.files) {
        $name=$entry.path
        if ($name -isnot [string] -or $name -cmatch '(^/|\\|(^|/)\.\.(/|$)|:)') { throw 'Invalid manifest path' }
        $path = Join-Path $Root $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHashValue $path) -cne $entry.exportSha256) { $errors.Add("Export hash mismatch: $name") }
        $isDerivative=$derivatives.ContainsKey($name)
        if ($isDerivative) {
            $origin=$derivatives[$name]
            if ($entry['sourcePath'] -isnot [string] -or $entry['sourceKind'] -isnot [string] -or
                $entry['transformation'] -isnot [string] -or $entry['packagingChanges'] -isnot [array] -or
                $entry['sourcePath'] -cne $origin[0] -or $entry.sourceSha256 -cne $origin[1] -or
                $entry.sourceKind -cne 'PowerShell tooling derivative of committed source blob' -or
                $entry['transformation'] -cne 'powershell-tooling-port-v1' -or !$entry.packagingChanges.Count) {
                $errors.Add("Invalid tooling derivative provenance: $name")
            }
            foreach ($change in $entry['packagingChanges']) {
                if ($change -isnot [string] -or !$change.Length) { $errors.Add("Invalid tooling derivative provenance: $name") }
            }
        } elseif ($entry.sourceSha256 -cne $entry.exportSha256 -and [IO.Path]::GetExtension($name) -cne '.md') {
            $errors.Add("Non-documentation source modification: $name")
        }
        if (!$isDerivative -and ($entry.Contains('sourcePath') -or $entry.Contains('transformation'))) { $errors.Add("Unapproved derivative metadata: $name") }
        $expectedCommit = if ($name -ceq 'skills/azure-local-operations-triage/SKILL.md') { '05304111ec9eb6c237156f68d4a915ae7f99fed8' }
        elseif ($name.StartsWith('tools/hybrid-server/') -or $name.StartsWith('tools/private-mcp/')) { '9eb5ddfd2fd1058185e2387afdb54d0379c479a3' }
        elseif ($name -cin $monitoringRefresh) { '1ceb2a76fd9efbf0bf736da10d665488f331afb6' }
        elseif ($name.StartsWith('docs/diagrams/')) { '0a195563ebb866c2f2da39b00cd9b11973a801c4' }
        elseif ($name.StartsWith('infra/hybrid-arc-connectivity/')) { 'c814605a2a78f4289314bae527a8fcf16f95bbb1' }
        else { 'c086d8d38f1a2d2db9242889ec715dad704749c2' }
        if ($entry.originCommit -cne $expectedCommit) { $errors.Add("Unexpected approved source revision: $name") }
        if ($entry.originRepository -cne 'janegilring/session-azure-sre-agent' -or $entry.originBlob -cnotmatch '^[0-9a-f]{40}$' -or $entry.sourceSha256 -cnotmatch '^[0-9a-f]{64}$') { $errors.Add("Invalid source origin: $name") }
    }
    $allowedGuids = @(
        '00000000-0000-0000-0000-000000000000','11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333',
        '1ec52169-b20b-4094-9937-2adb96c98d85','c046c0a1-f5ec-452e-bc35-58689380dfca',
        'acdd72a7-3385-48ef-bd42-f606fba81ae7','e79298df-d852-4c6d-84f9-5d13249d1e55',
        'b24988ac-6180-42a0-ab88-20f7382dd24c','749f88d5-cbae-40b8-bcfc-e573ddc772fa',
        '8e3af657-a8ff-443c-a75c-2fe8c4bcb635','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','cccccccc-cccc-cccc-cccc-cccccccccccc',
        'dddddddd-dddd-dddd-dddd-dddddddddddd','984b1aee-e2db-4c89-bbb0-0ac50b7fa91c',
        'd7d7f425-620e-419c-bc75-bfe367fc8e56','e5e4ef24-efc9-43c4-a4f7-0e7d2249f030',
        '11111111-1111-4111-8111-111111111111','00000000-0000-4000-8000-000000000000',
        '22222222-2222-4222-8222-222222222222','11fb06fb-712d-4ddd-98c7-e71bbd588830'
    )
    $testAddresses=@('10.0.0.0','10.1.0.0','999.0.0.0')
    $testAddressFiles=@('infra/sre-agent-starter/Test-Regression.ps1','scripts/Test-Package.ps1')
    $mcpAddresses=@(
        '0.0.0.0','0.0.0.1','127.0.0.0','127.0.0.1','192.0.0.0',
        '192.0.2.004','192.0.2.1','192.0.2.256','192.0.2.4','192.000.2.4',
        '198.051.100.0','198.51.100.0','198.51.100.1','198.51.100.19',
        '198.51.100.254','198.51.100.255','198.51.100.30','198.51.100.31',
        '198.51.100.18','198.51.100.20','198.51.100.32','198.51.256.0',
        '203.0.113.1','203.0.113.126','203.0.113.127','203.0.113.128','203.0.113.19',
        '203.0.113.2','203.0.113.40','203.0.113.64','203.0.113.65',
        '224.0.0.0','224.0.0.1','240.0.0.1','255.255.255.255'
    )
    $mcpFiles=@('tools/private-mcp/tests/BoundaryNetworkTests.cs','tools/private-mcp/tests/BoundaryTests.cs','tools/private-mcp/tests/ServerTests.cs','scripts/Test-Package.ps1')
    $deniedHosts=@('05fab6290805cb457e0cbeaa88c01755596b48cb80b0ee8afdf2e41145fc9aba')
    foreach ($name in $names) {
        $path=Join-Path $Root $name
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("Missing tracked file: $name"); continue }
        if (@($name.Split('/') | Where-Object { $_ -cin @('bin','obj','__pycache__','.local','.azure','.squad','TestResults') }).Count -or [IO.Path]::GetFileName($name).Contains('.local.')) { $errors.Add("Excluded export path: $name") }
        $extension=[IO.Path]::GetExtension($name)
        if ($name.StartsWith('tools/nic-sre-config/') -or ($name.StartsWith('tools/private-mcp/') -and $extension -cin @('.ps1','.py'))) { $errors.Add("Unapproved native configuration or lab operator script: $name") }
        if (($name.StartsWith('infra/') -or $name.StartsWith('tools/') -or $name.StartsWith('skills/')) -and $name -cnotin $allowlist) { $errors.Add("Unreviewed component path outside export allowlist: $name") }
        $text=Read-PackageText $path
        if ($name.StartsWith('docs/diagrams/') -and $name -cnotin $allowlist) { $errors.Add("Unapproved diagram asset: $name") }
        if ($extension -ceq '.svg') {
            $settings=[Xml.XmlReaderSettings]::new()
            $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit; $settings.XmlResolver=$null
            $reader=[Xml.XmlReader]::Create([IO.StringReader]::new($text),$settings)
            try {
                $xml=[Xml.XmlDocument]::new(); $xml.XmlResolver=$null; $xml.Load($reader)
                foreach ($element in $xml.SelectNodes('//*')) {
                    if ($element.LocalName -cin @('script','foreignObject','image') -or @($element.Attributes | Where-Object LocalName -CEQ 'href').Count) { $errors.Add("Active or externally referenced SVG content: $name") }
                }
            } finally { $reader.Dispose() }
        }
        if ($extension -ceq '.excalidraw') {
            $diagram=ConvertFrom-KitJson $text
            if ($diagram -isnot [Collections.IDictionary]) { throw "Unexpected diagram format: $name must be a JSON object" }
            if ($diagram['type'] -isnot [string] -or $diagram['type'] -cne 'excalidraw' -or
                (Test-JsonTruthy $diagram['files'])) { $errors.Add("Unexpected diagram format or embedded assets: $name") }
            if ($diagram['elements'] -isnot [array]) { throw "Unexpected diagram elements: $name must contain a JSON array" }
            foreach ($element in $diagram.elements) {
                if ($element -isnot [Collections.IDictionary]) { throw "Unexpected diagram element: $name must contain JSON objects" }
                if (Test-JsonTruthy $element['link']) { $errors.Add("Unexpected diagram link: $name") }
                if ($element['type'] -is [string] -and $element['type'] -ceq 'text' -and
                    (!(Test-JsonNumber $element['width']) -or !(Test-JsonNumber $element['height']) -or
                    $element['width'] -le 0 -or $element['height'] -le 0)) { $errors.Add("Invisible diagram text: $name") }
            }
        }
        $privateBinding = $text -cmatch '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
        foreach ($hostMatch in [regex]::Matches($text,'\b(?:[a-z0-9-]+\.)+[a-z]{2,}\b','IgnoreCase')) {
            if ((Get-TextHash $hostMatch.Value.ToLowerInvariant()) -cin $deniedHosts) { $privateBinding=$true }
        }
        if ($privateBinding) { $errors.Add("Known private binding or key marker: $name") }
        foreach ($match in [regex]::Matches($text,'\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b','IgnoreCase')) {
            if ($match.Value.ToLowerInvariant() -cnotin $allowedGuids) { $errors.Add("Unallowlisted GUID: $name"); break }
        }
        foreach ($match in [regex]::Matches($text,'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])')) {
            $value=$match.Value
            if ($value -ceq '1.0.0.0') { continue }
            if ($value -cin $testAddresses -and $name -cin $testAddressFiles) { continue }
            if ($value -cin $mcpAddresses -and $name -cin $mcpFiles) { continue }
            if ($name -ceq 'tools/private-mcp/boundary.example.json' -and $value -cin @('192.0.2.4','198.51.100.0')) { continue }
            if ($name -ceq 'tools/private-mcp/README.md' -and $value -cin @('0.0.0.0','224.0.0.0')) { continue }
            $errors.Add("Unallowlisted dotted address: $name")
        }
        if ($extension -ceq '.md') {
            foreach ($match in [regex]::Matches($text,'!?\[[^\]]*\]\(([^)]+)\)')) {
                $target=$match.Groups[1].Value
                if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { continue }
                $relative=[Uri]::UnescapeDataString($target.Split('#')[0])
                if ($relative -and !(Test-Path -LiteralPath (Join-Path (Split-Path $path) $relative))) { $errors.Add("Broken relative link: $name -> $target") }
            }
        }
    }
    if ($errors.Count) { throw ($errors -join "`n") }
    "PASS: $($names.Count) files; $($manifest.files.Count) source hashes; relative Markdown file links; scoped GUID/address/known-binding profile."
    'Not a general secret scan; no Azure, endpoint or native-agent acceptance implied.'
}
if ($MyInvocation.InvocationName -ne '.') { Test-Package $Root }
