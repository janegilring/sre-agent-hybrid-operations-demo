#Requires -Version 5.1
function Assert-HybridOwnedConfiguration {
    param($State, [string]$Root, [string]$Module)
    if ($State.SchemaVersion -ne 2 -or $State.EndpointName -cne 'HybridServer.ReadOnly' -or
        $State.RegistrationState -notin @('Pending','Registered') -or
        !$State.CallerIdentity -or !$State.CallerSid -or
        !$State.ConfigurationGuid -or [guid]$State.ConfigurationGuid -eq [guid]::Empty) {
        throw 'Invalid ownership receipt; no removal.'
    }
    $source = "$Root\Endpoint.pssc"
    $config = Import-PowerShellDataFile -LiteralPath $source
    $roles = @($config.RoleDefinitions.Keys)
    if ([guid]$config.Guid -ne [guid]$State.ConfigurationGuid -or
        $config.SessionType -ne 'RestrictedRemoteServer' -or $config.LanguageMode -ne 'NoLanguage' -or
        $config.RunAsVirtualAccount -ne $true -or
        @($config.RunAsVirtualAccountGroups).Count -ne 1 -or $config.RunAsVirtualAccountGroups -ne 'HybridServerReaders' -or
        @($config.ModulesToImport).Count -ne 1 -or $config.ModulesToImport -ne 'HybridServerReadOnly' -or
        @($config.ScriptsToProcess).Count -ne 1 -or $config.ScriptsToProcess -ine "$Root\Initialize.ps1" -or
        $roles.Count -ne 1 -or $roles[0] -cne $State.CallerIdentity) {
        throw 'Owned configuration setup mismatch; no removal.'
    }
    $role = $config.RoleDefinitions[$State.CallerIdentity]
    if (@($role.Keys).Count -ne 1 -or @($role.RoleCapabilityFiles).Count -ne 1 -or
        $role.RoleCapabilityFiles -ine "$Module\RoleCapabilities\HybridServerReader.psrc") {
        throw 'Owned role mapping mismatch; no removal.'
    }
    foreach ($name in 'VisibleAliases','VisibleCmdlets','VisibleFunctions','VisibleExternalCommands','VisibleProviders') {
        if (@($config[$name]).Count -and $null -ne $config[$name]) { throw 'Unexpected configuration visibility; no removal.' }
    }
    foreach ($name in 'RunAsUser','StartupScript','FunctionDefinitions','AliasDefinitions','VariableDefinitions',
        'EnvironmentVariables','AssembliesToLoad','TypesToProcess','FormatsToProcess','MountUserDrive') {
        if ($config[$name]) { throw 'Unexpected configuration execution setup; no removal.' }
    }
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ($State.Files.PSObject.Properties[$source].Value -ne $hash) { throw 'Source configuration hash mismatch.' }
    return $hash
}

function Get-HybridRegistrationRecord {
    param($Endpoint, [string]$SourceHash, [string]$ConfigurationGuid)
    if (!$Endpoint -or @($Endpoint).Count -ne 1 -or $Endpoint.Name -ine 'HybridServer.ReadOnly' -or
        [string]::IsNullOrWhiteSpace($Endpoint.ConfigFilePath) -or
        ![IO.Path]::IsPathRooted($Endpoint.ConfigFilePath)) { throw 'Invalid registered endpoint identity.' }
    $path = [IO.Path]::GetFullPath($Endpoint.ConfigFilePath)
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid registered configuration file.' }
    $parent = $item.Directory
    while ($null -ne $parent) {
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Registered configuration reparse point refused.' }
        $parent = $parent.Parent
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $config = Import-PowerShellDataFile -LiteralPath $path
    if ($hash -ne $SourceHash -or [guid]$config.Guid -ne [guid]$ConfigurationGuid) {
        throw 'Registered configuration does not match owned source.'
    }
    [pscustomobject]@{ Name = 'HybridServer.ReadOnly'; ConfigFilePath = $path
        ConfigurationGuid = $ConfigurationGuid; Sha256 = $hash }
}
