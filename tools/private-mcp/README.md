# Private MCP boundary: export gate

The ordinary-server JEA capability is available in
[hybrid-server](../hybrid-server/README.md). It needs domain Kerberos/WSMan, not
Arc or Azure Local. The MCP host is a separate deployment.

**No MCP executable source, installer or native connector configuration is
delivered in this snapshot.** The reviewed source contains fixed private-network
listener and source-subnet constants. The export instruction excludes
unallowlisted private network bindings and prohibits revising approved code.
Those requirements cannot both be met by copying that implementation today.
Its original example also contained real identity GUIDs and was not copied.
An explicit network-constant allowlist or separately reviewed generic source
revision is needed before export. No code was edited to bypass this gate.

## Prerequisites of the reviewed implementation

- Windows x64 and .NET 10 SDK; production uses Windows service hosting.
- Locked packages: JwtBearer/WindowsServices/ProtectedData 10.0.12,
  ModelContextProtocol.AspNetCore 2.2.0, PowerShell SDK 7.6.6.
- Dedicated nonadministrator domain service identity/gMSA and Kerberos access
  to the fixed `HybridServer.ReadOnly` JEA endpoint.
- Controlled DNS, a trusted LocalMachine certificate with private key, server
  EKU, matching SAN and working chain/revocation checks; private routing and
  the reviewed source network boundary. Reverse-proxy headers are not trusted.
- Explicit tenant, audience, caller client and caller object identifiers;
  the reviewed app role is `LocalBox.Diagnostics.Read`. These are operator
  prerequisites, not credentials to paste into source or an agent prompt.
- A protected runtime `boundary.local.json` beside the executable; environment
  variables are not a substitute in the reviewed host.

The [sanitized boundary example](boundary.example.json) is intentionally
incomplete and not runnable. [servers.example.json](servers.example.json)
illustrates the separate `Servers` allowlist; merge approved entries into the
private runtime configuration only after a boundary is separately accepted.

| Tool | Exact arguments |
| --- | --- |
| `get_server_facts` | `target` (opaque configured ID) |
| `get_server_service_state` | `target`, `service: "Spooler"` |
| `get_server_events` | `target`, `log: "System"` or `"Application"`, `maxCount: 1..50`, `lookbackMinutes: 1..1440` |

Discovery is enabled only for a nonempty validated server allowlist. No caller
hostname, script, credential, XPath or arbitrary command is accepted.

There is deliberately no pretend `dotnet build` quickstart pointing to absent
projects. Build/test and host setup instructions must accompany the approved
export. No endpoint registration, service installation, token issuance or Azure
call was attempted as a substitute.

On an independently installed host, remove `Servers` and restart its service to
disable the capability; use the guest's ownership-checked cleanup for JEA.
This repository has no whole-boundary installer or whole-boundary cleanup.
