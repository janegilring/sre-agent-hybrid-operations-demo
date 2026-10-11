# Publish and install the private MCP Windows service

**Manual operator runbook, not a tested appliance or native SRE installer.**
This original attendee guide replaces no source-lab deployment script. No live
AD, certificate, service or connector operation was performed to validate it.
Complete [gMSA and guest prerequisites](guest-setup.md) first. Use a new dedicated
broker; do not repoint a presenter's WORKGROUP service or reuse node credentials.

## Choose the deployment model

This guide uses **framework-dependent, Windows x64** publishing. Build with
the .NET 10 SDK; install supported **x64 .NET 10 and ASP.NET Core 10 runtimes**
on the broker (the latter installer includes the .NET runtime). Keep both
serviced at the current approved 10.0 patch. The Windows Desktop runtime alone
is insufficient. IIS, an IIS application pool and the ASP.NET Hosting Bundle
are not required for this direct Kestrel service.

For a new lab use supported, patched Windows Server 2022/2025 x64 and review
[.NET Windows support](https://learn.microsoft.com/dotnet/core/install/windows).
Use PowerShell 7.4+ for the SCM commands below; guest JEA and the AD steps use
Windows PowerShell 5.1. Neither installing the SDK nor running `dotnet build`
registers a service. Installing PowerShell 7 does not replace guest PS 5.1.

A self-contained publish would bundle runtimes and make runtime security updates
the artifact owner's responsibility. It is **not the recipe below**. Do not
copy only `PrivateMcp.exe`, enable trimming/single-file/AOT, or change runtime
identifiers without separately testing the PowerShell/MCP dependencies.

## Build and publish on a development machine

From the repository root; these commands require no Azure/domain login. Initial
restore requires approved NuGet access or an already-populated package cache.
Stop on any native command failure; do not remove `--locked-mode` to hide drift.

```powershell
dotnet restore tools\private-mcp\tests\PrivateMcp.Tests.csproj --locked-mode
if ($LASTEXITCODE -ne 0) { throw 'Locked restore failed.' }
dotnet test tools\private-mcp\tests\PrivateMcp.Tests.csproj --no-restore
if ($LASTEXITCODE -ne 0) { throw 'MCP tests failed.' }
dotnet publish tools\private-mcp\src\PrivateMcp.csproj `
    --configuration Release --runtime win-x64 --self-contained false `
    --no-restore --output tools\private-mcp\src\bin\publish\win-x64
if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
$publishDir = (Resolve-Path tools\private-mcp\src\bin\publish\win-x64).Path
Get-Item "$publishDir\PrivateMcp.exe", "$publishDir\PrivateMcp.dll",
    "$publishDir\PrivateMcp.deps.json", "$publishDir\PrivateMcp.runtimeconfig.json"
Get-Content "$publishDir\PrivateMcp.runtimeconfig.json"
```

The runtime configuration must reference `Microsoft.NETCore.App` and
`Microsoft.AspNetCore.App` 10.0; normal patch roll-forward applies. The documented
publish output is different from `src\bin\Release\net10.0` (build) and
`src\bin\Release\net10.0\win-x64` (RID build). Deploy the **entire publish
directory**, including dependencies and any subdirectories, not build/test
output. No `boundary.local.json` is supplied by publish.

Record the kit commit, SDK, runtime choice and SHA-256 inventory of all published
files in your private change record. Copy through an approved channel to an
administrator-controlled staging directory on the broker and compare the
inventory there. Do not run this binary or test a connection on the build host.
Do not commit binaries, archives, real configuration or receipts.

## Protect a new installation directory on the broker

The following examples use `C:\Program Files\HybridDiagnosticsMcp` and the sample
gMSA `EXAMPLE\mcpRead$`. Substitute your values consistently. Run elevated
PowerShell 7.4+ **on the broker**, with no concurrent installer. Record original
absence of the directory, SCM name and Event Log source before creation. This
is create-only: any collision or partial failure requires inspection, not
overwrite, automated adoption or blind rerun.

```powershell
$ErrorActionPreference = 'Stop'
$serviceName = 'LocalBoxPrivateMcp'
$account = 'EXAMPLE\mcpRead$'
$installRoot = 'C:\Program Files\HybridDiagnosticsMcp'
$publishDir = 'C:\McpStage\win-x64' # Your verified, administrator-owned staging copy.
if (Test-Path -LiteralPath $installRoot) { throw 'Installation directory already exists.' }
if (Get-CimInstance Win32_Service -Filter "Name='$serviceName'") {
    throw 'SCM service name already exists; do not replace it.'
}
if ([System.Diagnostics.EventLog]::SourceExists($serviceName)) {
    throw 'Event Log source already exists; investigate its owner.'
}
if (-not (Test-Path -LiteralPath "$publishDir\PrivateMcp.exe" -PathType Leaf)) {
    throw 'Verified publish output is missing.'
}
$serviceSid = ([System.Security.Principal.NTAccount]::new($account)).Translate(
    [System.Security.Principal.SecurityIdentifier])
$adminsSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$systemSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
New-Item -ItemType Directory -Path $installRoot | Out-Null
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($adminsSid)
foreach ($sid in @($adminsSid, $systemSid)) {
    $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
    $serviceSid, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
Set-Acl -LiteralPath $installRoot -AclObject $acl
Get-ChildItem -LiteralPath $publishDir -Force |
    Copy-Item -Destination $installRoot -Recurse
Get-Acl -LiteralPath $installRoot | Format-List Owner, AccessToString
```

Review staging for unexpected files/reparse points before copying. Keep normal
secured `Program Files` parents; do not generalize this ACL reset to an existing
or shared directory. Service identity gets read/execute, not modify, ownership,
service-control rights or membership in Administrators. Verify inherited ACLs
and Effective Access on the installed files, including the configuration.
Keep receipts outside the deployment directory in an administrator-only store.
This host writes audits to Event Log; it does not need a writable binary folder.

## Private configuration, certificate and network gates

Use the [configuration contract](../tools/private-mcp/README.md#explicit-configuration-and-prerequisites)
and the two JSON examples. Author `boundary.local.json` **inside the newly
protected directory**. Do not copy it from a source environment or place it
in user-writable staging. Preserve the restrictive inherited ACL; the service
may read it, never write it. Use these fields, with your own values:

| Setting | Required value / common error |
| --- | --- |
| `TenantId` | Directory issuing the caller's application token |
| `Audience` | Exact API audience GUID accepted by this API's v2 token; not an ARM scope or the agent's resource ID |
| `CallerClientId` | Authorized caller's application/client ID (`azp` claim) |
| `CallerObjectId` | That caller service principal's object ID (`oid`) in the configured tenant; not the API app's object ID |
| `Hostname`, `CertificateThumbprint` | Controlled DNS SAN and exact certificate in `LocalMachine\My` |
| `ListenAddress`, `AllowedSourceCidrs` | Actual local IPv4 and narrow actual TCP source subnet(s)/host(s); example networks do not work in your lab |
| `HostTarget` | **Add this property** and set the broker's exact computer name; omitted value is the legacy `LocalBox-Client` |
| `Port` | `8443` |
| `NodeIdentityEnabled`, `ReadCapabilitiesEnabled` | Both `false` for ordinary servers |
| `Servers` | One entry with `Id`, guest `Hostname` FQDN, expected `Machine`, and `ConnectingIdentity` (`EXAMPLE\mcpRead$`) |

In JSON, encode the identity as `"EXAMPLE\\mcpRead$"`. The two examples are
fragments to merge, not two config files to load. No environment variable,
CLI switch, `ASPNETCORE_URLS`, `appsettings.json` or current working directory
overrides these settings. Configuration is loaded once beside the executable.
An edit requires a separately approved service stop/start.

The Entra owner must arrange an API application accepting **v2 application-only
tokens** with the application role value `LocalBox.Diagnostics.Read`, and assign
that exact role to the intended caller service principal. Verify tenant, issuer,
audience, `ver=2.0`, `azp`, `oid`, absence of `scp`, and role against this implementation before
authorizing a client. This guide provisions no app, credentials or grants.
Delegated user sign-in, API keys and generic Azure Reader access are not substitutes.

Have the PKI owner install an approved server-authentication certificate with a
private key into **Local Computer -> Personal**. SAN must contain `Hostname`;
the chain, validity, server EKU and online revocation checks must pass. No
development-certificate/trust bypass is supported.

On the broker, use `certlm.msc`, locate the **exact thumbprint**, then All Tasks
-> **Manage Private Keys**. Add only the gMSA with **Read**, preserve existing
owner/system/PKI entries, and record that added ACE. Do not grant Full Control,
grant the entire MachineKeys/Keys directory, export a PFX, or change store-wide
ACLs. If the provider has no Manage Private Keys action (for example an HSM),
stop for the PKI owner's provider-specific procedure. Renewals may have a new
key/thumbprint and need a separate ACE, config update and acceptance.

Network owners must separately validate:

- Client -> broker: private DNS resolves `Hostname`; TCP 8443 reaches the exact
  listener; host firewall and upstream controls admit only approved sources.
  An optional TCP forwarder preserves end-to-end TLS and must not terminate it.
- Broker -> guest: domain FQDN, TCP 5985, Kerberos with message encryption,
  existing guest WinRM SPNs; no Basic/TrustedHosts/CredSSP/NTLM fallback. The
  compiled executor does **not** support a 5986-only endpoint.
- Broker/guest -> AD DNS/DC/time services as required by domain policy; broker
  -> Entra signing metadata and certificate chain/revocation endpoints.
  Proxy/service-account egress must work without an interactive installer login.

Do not open public WinRM or permit an entire network because a narrow source
rule is wrong. No firewall rule, VPN or DNS server is installed by this guide.

### Native SRE connector is a separate availability gate

The endpoint is **`https://<your-TLS-hostname>:8443/mcp`**, Streamable HTTP,
not stdio or a browser page. The service supplies no interactive OAuth
discovery/authorization flow. Keep these documented surfaces distinct:

| Official source / section (reviewed October 11, 2026) | What it establishes |
| --- | --- |
| [Network integration: traffic routing summary](https://learn.microsoft.com/azure/sre-agent/network-integration#how-azure-vnet-mode-works) | **Remote MCP servers can route through your VNet**, or through the infra network when that toggle is enabled. The same table separately labels generic connector traffic as public; do not apply that row to every remote MCP call. |
| [Network integration: bypass controls](https://learn.microsoft.com/azure/sre-agent/network-integration#virtual-network-bypass-controls) | MCP server access toggle **on** uses public/platform egress. Keep it off for the intended private route, with working VNet DNS/routes/firewall rules. Agent inbound private endpoints are a different, unsupported direction. |
| [MCP connector tutorial: step 1](https://learn.microsoft.com/azure/sre-agent/mcp-connector#step-1-add-the-mcp-connector) | Builder -> Connectors -> MCP Server asks for server-dependent authentication, including managed identity where supported. The tutorial is not this API's app-role provisioning recipe. |
| [MCP connectors: Authentication](https://learn.microsoft.com/azure/sre-agent/mcp-connectors#authentication) | The method table describes managed identity for stdio and interactive OAuth for public HTTPS. That table alone does not prove that every installed remote-MCP configuration lacks app-only authentication. |

These sources establish a private **network route**, not a complete portable
recipe for assigning this API role and obtaining/renewing exactly the token this
boundary validates. Inspect the current supported authentication fields in your
installed product with the identity owner. Record the selected caller principal,
audience, app-role assignment, token acquisition/renewal mechanism and tested
route without recording tokens. This kit's missing provisioning/acceptance
recipe is an **attendee gate, not a blanket product-unsupported claim**.

**Stop before promising native SRE access** unless the installed product and
your approved connector/adapter can prove private reachability and renewable
application-only tokens for this exact audience/caller. A static bearer token
copied into a header is not a lifecycle solution and is not offered here.
Do not publish the broker, relax JWT checks, or run this Windows/.NET 10 binary
inside the agent's stdio container as a workaround. A local approved MCP client
and a native SRE connector are different acceptance stages.

## Register the service without starting it

Continue in the same elevated **PowerShell 7.4+** broker session after all
previous gates. The service name is fixed for compatibility, despite not
requiring LocalBox. `AddWindowsService` in `Program.cs` integrates with SCM;
**it does not create the SCM entry**.

```powershell
if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    throw 'Use PowerShell 7.4+ for the native quoting in this block.'
}
$PSNativeCommandArgumentPassing = 'Standard'
$exePath = Join-Path $installRoot 'PrivateMcp.exe'
$binaryPath = '"' + $exePath + '"'
if (-not (Test-Path -LiteralPath "$installRoot\boundary.local.json" -PathType Leaf)) {
    throw 'Protected boundary configuration is missing.'
}
if (Get-CimInstance Win32_Service -Filter "Name='$serviceName'") {
    throw 'Service collision; do not change an existing registration.'
}
[System.Diagnostics.EventLog]::CreateEventSource($serviceName, 'Application')
& "$env:SystemRoot\System32\sc.exe" create $serviceName `
    binPath= $binaryPath start= demand obj= $account
if ($LASTEXITCODE -ne 0) { throw 'SCM creation failed; inspect partial state, do not retry blindly.' }
$installed = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
if ($installed.PathName -cne $binaryPath -or $installed.StartName -ine $account -or
    $installed.StartMode -ne 'Manual' -or $installed.State -ne 'Stopped') {
    throw 'Unexpected SCM path/account/start state. Do not start.'
}
$installed | Select-Object Name, PathName, StartName, StartMode, State
& "$env:SystemRoot\System32\sc.exe" qmanagedaccount $serviceName
if ($LASTEXITCODE -ne 0) { throw 'SCM managed-account query failed.' }
```

The embedded quotes must survive into SCM `PathName` because Program Files
contains spaces. This is why the block requires current PowerShell native
argument passing and uses `sc.exe`, not the `sc` alias. **Omit `password=`**:
SCM must use a null password for the managed account. The trailing `$` is part
of the gMSA logon name. Verify `qmanagedaccount` reports a managed account;
otherwise stop for identity/SCM diagnosis, not a password prompt.

Creating the Event Log source requires elevation, but writing metadata-only
audits must work under the runtime identity. Do not give the gMSA permission
to provision Event Log sources. Existing sources cause an ownership review,
not an implicit reuse/deletion. There are no recovery/restart actions and no
automatic startup configured by this recipe.

## Acceptance and troubleshooting

Record a UTC start time and separately approve this **first start**:

```powershell
$startedUtc = [DateTime]::UtcNow
Start-Service -Name $serviceName -WhatIf
# After approval:
Start-Service -Name $serviceName -ErrorAction Stop
(Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
$running = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
if ($running.State -ne 'Running' -or $running.ProcessId -eq 0 -or
    $running.StartName -ine $account -or $running.PathName -cne $binaryPath) {
    throw 'Service runtime/account verification failed.'
}
$running | Select-Object Name, State, StartName, ProcessId, PathName
Get-NetTCPConnection -State Listen -LocalPort 8443 |
    Select-Object LocalAddress, LocalPort, OwningProcess
```

Check the listener address and owning PID match the recorded service. Recheck
state after the first request; transient `Running` is not readiness. The
program refuses LocalSystem/administrator runtime identities. Do not test by
launching the EXE in the elevated installer console or increase its privileges
when startup fails.

| Layer | Required evidence / stop condition |
| --- | --- |
| gMSA/SCM | `Test-ADServiceAccount=True`, effective service-logon/GPO rights, exact SCM account, managed-account status, stable Running state |
| TLS/network | Correct DNS/SAN/thumbprint, trusted/revocation-valid chain, PID/address/8443 match and actual permitted source; no certificate-check bypass |
| Authentication | Approved client supplies renewable app-only tokens; missing token is rejected and wrong tenant/caller/role never reaches JEA |
| Discovery | `get_server_facts`, `get_server_service_state`, `get_server_events` visible for configured `Servers`; legacy node names may remain discoverable but disabled calls must fail |
| Guest reads | Sequential facts, `Spooler`, System/Application events; expected connecting gMSA and nonadmin virtual execution identity, fresh UTC/correlation, each required provider succeeds |
| Denials | Unlisted target/service/log, extra command arguments and arbitrary commands denied; do not broaden access for a failed test |
| Audit | Authenticated request correlation present in Application source `LocalBoxPrivateMcp`; retain only approved redacted metadata |
| Native agent | Independently prove connector route, token renewal, exact selected tools and fresh correlated calls; source-lab acceptance does not transfer |

Use the [exact tool arguments](../tools/hybrid-server/README.md#components-and-contracts)
with an approved authenticated MCP client. For initial event checks use
`maxCount: 3`, `lookbackMinutes: 60`; an empty sample is not health. Do not
publish raw event messages or a bearer token. Protocol fake-executor tests do
not establish deployed negative-case or guest provider acceptance.

On failure inspect the bounded time window privately in Event Viewer:
System -> Service Control Manager (logon/path/start errors), Application ->
`.NET Runtime`/`Application Error` and `LocalBoxPrivateMcp` (when available).
The boundary deliberately filters most logging; a missing audit event is not
success or a reason to enable token/body logging. Check runtime installation,
configuration validation, certificate key access, metadata/revocation egress,
DNS/SPNs, JEA caller mapping and provider ACLs in that order. Respect the
executor's cancellation/disposal gate; do not pile up repeated tool calls.

## Rollback and uninstall

There is no automatic upgrade/rollback installer. Keep the prior approved
artifact/config hashes and ownership record for any later maintenance.
Never overwrite running binaries or downgrade only half the dependency set.
Stop only this service after calls drain, stage/review the complete replacement,
and separately approve start and acceptance. Rollback must restore a compatible
artifact **and** config; current listener/source settings are mandatory.

For a fresh-install failure, leave partial state for inspection. For teardown,
first remove only your connector/tool references, confirm no other consumer,
then repopulate the expected account/path/name from the **original private
installation record**, not from the current SCM object. Compare artifact
hashes, directory ACL and source ownership; drift blocks unattended removal.

```powershell
$serviceName = 'LocalBoxPrivateMcp'
$account = 'EXAMPLE\mcpRead$'
$binaryPath = '"C:\Program Files\HybridDiagnosticsMcp\PrivateMcp.exe"'
$owned = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
if (-not $owned -or $owned.PathName -cne $binaryPath -or $owned.StartName -ine $account) {
    throw 'SCM identity drift or absence: stop for ownership review.'
}
Stop-Service -Name $serviceName -WhatIf
# After original ownership, dependencies and drained calls are reviewed:
Stop-Service -Name $serviceName -ErrorAction Stop
(Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
& "$env:SystemRoot\System32\sc.exe" delete $serviceName
if ($LASTEXITCODE -ne 0) { throw 'SCM deletion failed.' }
```

SCM deletion can remain pending while Services/other handles are open. Close
those handles and verify the exact service is absent before removing files;
do not kill unrelated processes or reboot a shared host for this cleanup.
Deletion does not delete binaries or reverse configuration.

Remove only the recorded files in the dedicated installation directory after
reviewing hashes and unexpected children/reparse points. Remove the Event Log
**source** only if this installation created it and no other consumer uses it
(`Remove-EventLog -Source LocalBoxPrivateMcp` in elevated Windows PowerShell
5.1); **never remove/clear the Application log**. Retain audit evidence under
the owner's retention policy. A shared/pre-existing source stays untouched.

Roll back only your exact certificate-key ACE, firewall rules and service-logon
policy entry, preserving original entries. Do not delete a shared certificate,
key, trust root, OU, KDS root key or domain. Follow the [guest and gMSA cleanup
sequence](guest-setup.md#scoped-teardown) for the remaining owned resources.
Keep receipts until absence/restoration is independently verified.

## Sources and validation scope

Microsoft references reviewed October 11, 2026:
[ASP.NET Core Windows services](https://learn.microsoft.com/aspnet/core/host-and-deploy/windows-service?view=aspnetcore-10.0),
[dotnet publish](https://learn.microsoft.com/dotnet/core/tools/dotnet-publish),
[CreateService account/password contract](https://learn.microsoft.com/windows/win32/api/winsvc/nf-winsvc-createservicew),
[PowerShell native quoting](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.6).
The kit's offline checks validate snippets/contracts and publish outputs, not
real SCM registration, gMSA logon, TLS key access or a native SRE connection.
