#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Standalone compilation is local; no Azure authentication or resource calls.
$compiled = & bicep build "$PSScriptRoot\..\main.bicep" --stdout
if ($LASTEXITCODE -ne 0) { throw 'Bicep compilation failed.' }
$template = ($compiled -join "`n") | ConvertFrom-Json -Depth 100
$resources = if ($template.resources -is [array]) { @($template.resources) } else {
    @($template.resources.PSObject.Properties | ForEach-Object Value)
}
if ($resources.Count -ne 1) { throw 'Expected one shared five-rule resource loop.' }
$rule = $resources[0]
$suffixes = @($template.variables.definitions | ForEach-Object suffix)
if (($suffixes -join ',') -ne 'heartbeat,cpu,memory,disk,coverage' -or
    $rule.type -ne 'Microsoft.Insights/scheduledQueryRules' -or
    $rule.copy.count -ne "[length(variables('definitions'))]") { throw 'Five-rule loop drift.' }
$p = $rule.properties
if ($p.PSObject.Properties.Name -contains 'autoMitigate') { throw 'Incompatible autoMitigate emitted with resolveConfiguration.' }
if ($p.resolveConfiguration.autoResolved -ne $true -or
    $p.resolveConfiguration.timeToResolve -ne "[format('PT{0}M', parameters('recoveryMinutes'))]" -or
    $template.parameters.recoveryMinutes.defaultValue -ne 10) { throw 'Explicit recovery contract drift.' }
if ($p.enabled -ne "[parameters('enabled')]" -or $template.parameters.enabled.defaultValue -ne $true -or
    $rule.name -ne "[format('{0}-{1}', parameters('namePrefix'), variables('definitions')[copyIndex()].suffix)]" -or
    $p.scopes.Count -ne 1 -or $p.scopes[0] -ne "[parameters('workspaceResourceId')]" -or
    $rule.tags.'hybrid-monitoring-owner' -ne "[parameters('ownerToken')]") { throw 'Enabled/name/scope/ownership contract drift.' }
Write-Host 'PASS: local Bicep compile; all five rules share exclusive explicit recovery, ten-minute default and enabled/name/scope/ownership contracts.'
