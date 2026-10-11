#Requires -Version 7.5
. "$PSScriptRoot\..\scripts\TestSupport.ps1"
. "$PSScriptRoot\..\scripts\Test-Package.ps1"
$validatorPath = [IO.Path]::GetFullPath("$PSScriptRoot\..\scripts\Test-Package.ps1")
$scratch = Join-Path ([IO.Path]::GetTempPath()) "package-contract-$([guid]::NewGuid())"
$null = New-Item -ItemType Directory -Path "$scratch\packaging" -Force
$script:checks = 0
function Write-Fixture([string]$Name, [string]$Text) {
    $path=Join-Path $scratch $Name
    $null=New-Item -ItemType Directory -Path (Split-Path $path) -Force
    [IO.File]::WriteAllText($path,$Text,[Text.UTF8Encoding]::new($false))
}
function Write-Manifest($Entries=@()) {
    Write-Fixture 'packaging\source-manifest.json' (ConvertTo-Json @{files=@($Entries)} -Depth 30)
    Write-Fixture 'packaging\export-paths.json' (ConvertTo-Json -InputObject @($Entries | ForEach-Object { $_.path }))
}
function New-Entry([string]$Name) {
    $hash=Get-FileHashValue (Join-Path $scratch $Name)
    @{
        path=$Name; sourceSha256=$hash; exportSha256=$hash
        sourceKind='committed source blob'; originRepository='janegilring/session-azure-sre-agent'
        originCommit='9eb5ddfd2fd1058185e2387afdb54d0379c479a3'
        originBlob=('a'*40); packagingChanges=@()
    }
}
function Reject([scriptblock]$Change,[string]$Pattern,[scriptblock]$Reset) {
    try {
        & $Change
        Assert-Rejected { Test-Package $scratch } $Pattern
        $script:checks++
    } finally { & $Reset }
}
try {
    & git -C $scratch init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize isolated fixture repository' }
    Write-Manifest
    Write-Fixture 'README.md' '[local](note%20file.md#heading)'
    Write-Fixture 'note file.md' '# Safe fixture'
    Write-Fixture 'empty-assets.excalidraw' '{"type":"excalidraw","files":{},"elements":[]}'
    Write-Fixture 'safe.svg' '<svg><rect width="1" height="1"/></svg>'
    $null=Test-Package $scratch
    foreach ($pair in @(
        @('extra.txt',('-----BEGIN '+'PRIVATE KEY-----'),'private binding or key'),
        @('extra.txt',([guid]::NewGuid().ToString()),'Unallowlisted GUID'),
        @('extra.txt',([string]::Join('.',@('10','42','7','9'))),'Unallowlisted dotted address'),
        @('extra.txt',([string]::Join('.',@('198','51','100','0'))),'Unallowlisted dotted address'),
        @('extra.local.json','{}','Excluded export path'),
        @('bin/extra.txt','test','Excluded export path'),
        @('tools/nic-sre-config/extra.txt','test','Unapproved native'),
        @('tools/private-mcp/extra.ps1','test','lab operator script'),
        @('infra/extra.ps1','test','Unreviewed component'),
        @('skills/extra.md','test','Unreviewed component'),
        @('docs/diagrams/extra.svg','<svg/>','Unapproved diagram')
    )) {
        $name,$text,$pattern=$pair
        Reject { Write-Fixture $name $text } $pattern { Remove-Item -LiteralPath (Join-Path $scratch $name) }
    }
    Reject { Write-Fixture 'README.md' '[bad](missing.md)' } 'Broken relative link' { Write-Fixture 'README.md' '[local](note%20file.md#heading)' }
    Reject { Write-Fixture 'invalid.svg' '<svg>' } 'Unexpected end|unclosed' { Remove-Item -LiteralPath "$scratch\invalid.svg" }
    Reject { Write-Fixture 'invalid.excalidraw' '{' } 'JSON|depth|object' { Remove-Item -LiteralPath "$scratch\invalid.excalidraw" }
    foreach ($invalid in @('{"files":[],}','{/*comment*/"files":[]}')) {
        Reject { Write-Fixture 'packaging\source-manifest.json' $invalid } 'JSON|trailing comma|invalid start|Expected' { Write-Manifest }
    }
    Reject { [IO.File]::WriteAllBytes("$scratch\invalid.txt",[byte[]]@(0xc3,0x28)) } 'translate bytes|Unicode|fallback|convert' { Remove-Item -LiteralPath "$scratch\invalid.txt" }
    foreach ($svg in @('<svg><script/></svg>','<svg><foreignObject/></svg>','<svg><image/></svg>','<svg xmlns:x="urn:x"><a x:href="https://example.test"/></svg>')) {
        Reject { Write-Fixture 'test.svg' $svg } 'Active or externally referenced SVG' { Remove-Item -LiteralPath "$scratch\test.svg" }
    }
    foreach ($diagram in @(
        @{type='wrong';elements=@()}, @{type='excalidraw';files=@{asset=@{}};elements=@()},
        @{type='excalidraw';elements=@(@{type='rectangle';link='https://example.test'})},
        @{type='excalidraw';elements=@(@{type='text';width=0;height=1})},
        @{type='excalidraw';elements=@(@{type='text';width=1})}
    )) {
        Reject { Write-Fixture 'test.excalidraw' (ConvertTo-Json $diagram -Depth 10) } 'diagram format|diagram link|Invisible diagram text' { Remove-Item -LiteralPath "$scratch\test.excalidraw" }
    }
    $name='tools/hybrid-server/fixture.ps1'
    Write-Fixture $name "'safe'"
    $entry=New-Entry $name; Write-Manifest @($entry)
    $null=Test-Package $scratch
    Reject { Write-Fixture $name "'changed'" } 'Export hash mismatch' { Write-Fixture $name "'safe'" }
    Reject { $e=Copy-JsonValue $entry; $e.sourceSha256='b'*64; Write-Manifest @($e) } 'Non-documentation source modification' { Write-Manifest @($entry) }
    Reject { $e=Copy-JsonValue $entry; $e.originCommit='b'*40; Write-Manifest @($e) } 'Unexpected approved source revision' { Write-Manifest @($entry) }
    Reject { $e=Copy-JsonValue $entry; $e.transformation='powershell-tooling-port-v1'; Write-Manifest @($e) } 'Unapproved derivative metadata' { Write-Manifest @($entry) }
    Reject { Write-Fixture 'packaging\export-paths.json' '[]' } 'differs from explicit export' { Write-Manifest @($entry) }
    Reject { Write-Manifest @($entry,$entry) } 'Duplicate manifest path' { Write-Manifest @($entry) }
    & git -C $scratch add -- $name
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage fixture' }
    Reject { Remove-Item -LiteralPath (Join-Path $scratch $name) } 'Missing tracked file' { Write-Fixture $name "'safe'" }
    $derivedName='infra/hybrid-monitoring/tests/Test-Queries.ps1'
    Write-Fixture $derivedName "'translated'"
    $derived=New-Entry $derivedName
    $derived.sourceSha256='03788334a7a2a97e5eae588a0609a978b7e3c943202b370c023a5fd8f66cbb32'
    $derived.sourcePath='infra/hybrid-monitoring/tests/test_queries.py'
    $derived.sourceKind='PowerShell tooling derivative of committed source blob'
    $derived.transformation='powershell-tooling-port-v1'
    $derived.originCommit='c086d8d38f1a2d2db9242889ec715dad704749c2'
    $derived.packagingChanges=@('Explicit tooling translation')
    Write-Manifest @($entry,$derived)
    $null=Test-Package $scratch
    foreach ($field in @('sourcePath','sourceSha256','sourceKind','transformation')) {
        Reject { $e=Copy-JsonValue $derived; $e[$field]='invalid'; Write-Manifest @($entry,$e) } 'derivative provenance' { Write-Manifest @($entry,$derived) }
    }
    # Exercise hostname hashing with a synthetic digest in a disposable validator.
    $copy=(Get-Content $validatorPath -Raw).Replace('05fab6290805cb457e0cbeaa88c01755596b48cb80b0ee8afdf2e41145fc9aba',(Get-TextHash 'blocked.example.test'))
    Write-Fixture 'validator.ps1' $copy
    Copy-Item -LiteralPath "$PSScriptRoot\..\scripts\Read-StrictJson.ps1" -Destination "$scratch\Read-StrictJson.ps1"
    Write-Fixture 'extra.txt' 'BLOCKED.EXAMPLE.TEST'
    $output=& pwsh -NoProfile -File "$scratch\validator.ps1" -Root $scratch 2>&1
    Assert-That ($LASTEXITCODE -ne 0 -and "$output" -match 'Known private binding or key marker: extra.txt') 'case-insensitive hostname digest rejection'
    $script:checks++
    Remove-Item -LiteralPath "$scratch\validator.ps1","$scratch\extra.txt","$scratch\Read-StrictJson.ps1"
    $null=Test-Package $scratch
    "PASS: package positive fixtures and $script:checks rejecting mutations; real package untouched."
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
