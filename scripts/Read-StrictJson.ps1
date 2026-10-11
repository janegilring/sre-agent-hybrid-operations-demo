#Requires -Version 7.5
function ConvertFrom-KitJson {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    # ConvertFrom-Json alone accepts comments/trailing commas that the old gates rejected.
    $document = [Text.Json.JsonDocument]::Parse($Text)
    $document.Dispose()
    ConvertFrom-Json -InputObject $Text -AsHashtable -DateKind String -NoEnumerate
}
