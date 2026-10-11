# Private MCP boundary: portable source

One boundary implementation supports ordinary Windows servers without LocalBox.
The full `src` directory is required; retain the existing node readers and their
module/credential paths for LocalBox compatibility. No separate MCP fork or
operator deployment scripts are required in a source export.

## Build and test

From this directory with the .NET 10 SDK:

```powershell
dotnet restore .\tests\PrivateMcp.Tests.csproj --locked-mode
dotnet test .\tests\PrivateMcp.Tests.csproj --no-restore
dotnet build .\src\PrivateMcp.csproj --configuration Release --no-restore
dotnet publish .\src\PrivateMcp.csproj --configuration Release --runtime win-x64 `
    --self-contained false --no-restore --output .\src\bin\publish\win-x64
```

Production requires Windows. Deploy the complete **publish** directory, not
just the executable or the build directory. This explicit framework-dependent
choice requires supported x64 .NET 10 and ASP.NET Core 10 runtimes on the host.
Place a protected operator-authored `boundary.local.json` beside the published
`PrivateMcp.exe`. Follow the [compiled service installation guide](../../docs/mcp-service-install.md)
for artifact/config ACLs, TLS private-key Read access, Event Log source,
quoted SCM registration as gMSA, first start, acceptance and scoped uninstall.
Create/test the [dedicated nonadmin gMSA](../../docs/guest-setup.md) separately.
`AddWindowsService` is hosting integration, **not service registration**.
Private routing, DNS, firewall and native token provisioning remain manual
operator responsibilities. The service name remains `LocalBoxPrivateMcp` for
compatibility; it does not require a LocalBox machine for ordinary-server reads.

## Explicit configuration and prerequisites

- Start from `boundary.example.json`; all GUIDs are intentionally empty
  placeholders and validation rejects the unchanged sample. Supply the tenant,
  API audience, caller client and caller object IDs. Entra application-only v2
  JWTs must have the exact `LocalBox.Diagnostics.Read` role. Issuer, audience,
  signature, expiry and caller checks still precede every MCP route.
- Set `ListenAddress` to one canonical dotted-decimal IPv4 address on the host.
  Wildcards, unspecified/zero-network, multicast/reserved, IPv6 and abbreviated,
  hexadecimal or integer address notation are rejected. Port remains **8443**.
- Set `AllowedSourceCidrs` to **1–16 explicit canonical IPv4 networks** for the
  actual packet sources (for example the approved delegated subnet).
  RFC 5737 sample addresses are documentation only, never production defaults.
  Prefixes `/1`–`/30` are accepted only when the entire range is unicast
  (outside `0.0.0.0/8` and `224.0.0.0/3`); choose the narrowest approved subnet.
  Host bits and noncanonical notation are errors. Exact `/32` unicast host
  rules are also supported for a narrowly scoped private TCP forwarder.
  `/0` and `/31` remain rejected. Subnet rules exclude network and broadcast, preserving
  `/27` host offsets **1–30**. Multiple rules form an explicit union.
  IPv4-mapped IPv6 packet sources are matched as IPv4; other IPv6 is denied.
  Loopback is not a bypass and needs an explicitly configured source rule.
- `HostTarget` is the operator-configured boundary identity (1–15 ASCII
  alphanumeric/hyphen characters, starting alphanumeric), independently checked
  against the running machine. It defaults to `LocalBox-Client` for backwards
  compatibility. Set it to the exact approved computer name on another host;
  callers cannot choose an arbitrary boundary hostname.
- `Hostname` must be a controlled TLS DNS name. Install its trusted certificate
  with private key in `LocalMachine\My`; grant only the service identity key
  read access. Configure its thumbprint. SAN hostname, server EKU, chain,
  validity and online revocation checks must pass. TLS terminates here using
  TLS 1.2/1.3; no trusted proxy forwarding or TLS-offload mode is introduced.
  `Forwarded` and `X-Forwarded-For` cannot authorize a caller. Browser Origin
  requests, HTTP and mismatched hosts remain denied. Entra metadata and
  certificate revocation endpoints must be reachable.
- Keep `NodeIdentityEnabled` and `ReadCapabilitiesEnabled` false for ordinary
  servers. Merge the `Servers` array from `servers.example.json` into the same
  private configuration with your approved IDs, FQDNs, machine names and domain
  connecting identity. Up to eight servers are supported. Omitted/empty
  `Servers` keeps the three ordinary-server tools unregistered.
- The target-side **HybridServerReadOnly module and `HybridServer.ReadOnly` JEA
  endpoint are a separate dependency**: see `..\hybrid-server\README.md`.
  They require separately reviewed guest installation, domain/Kerberos DNS and
  SPNs, scoped encrypted WSMan access and effective local read permissions.
  No fallback authentication, saved node credentials, arbitrary endpoint,
  command, script, credential, XPath or authority/RPC path is accepted through
  MCP. Tools remain bounded facts, Spooler state, and System/Application events.
  LocalBox-specific tool names remain discoverable for API compatibility;
  disabled node capabilities reject calls, and boundary identity requires the
  configured exact host. Ordinary-server tools do not depend on node calls.

## Breaking configuration migration: before any upgrade

Both `ListenAddress` and `AllowedSourceCidrs` are now **required**. Missing,
empty or invalid values intentionally prevent startup; there is no private
address or allow-any fallback. Before upgrading, an operator must explicitly
add the existing approved listener and canonical source subnet to the
**private** deployment configuration. Reconstruct the previous `/27` policy
with that subnet's canonical network address: host offsets 1–30 are admitted,
network offset 0, broadcast offset 31 and outside addresses remain denied.
Actual deployment values belong only in the private migration receipt/config.
Preserve all tenant/caller/audience, TLS, role, node and server settings.

Source edits/builds do not modify the deployed binary, configuration or service.
Configuration is loaded once from the executable directory, not environment
variables or command-line overrides. Plan a separately approved upgrade and
restart only after reviewing the private migration and negative tests.

## Export review gate

Export candidates are this README, `src` (excluding `bin`/`obj`), the C# test
files and test project, project lockfiles and the two documentation-only JSON
examples. Include the separately reviewed hybrid-server dependency only
when selecting that component. Exclude `*.local.json`, binaries, `bin`, `obj`,
`TestResults`, publish output, archives, private receipts, raw logs and all
private-mcp operator `.ps1`/inventory scripts (including their dependent
PowerShell/Python tests). Retained LocalBox identifiers,
app role and module paths are compatibility contracts, not ordinary-server
deployment bindings. Re-scan the final candidate and obtain review approval
before packaging or publishing; this change performs neither.
