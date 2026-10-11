# Ordinary Windows server read capability

Read-only, offline-tested Windows JEA source. Installation and native SRE
acceptance in your environment require the explicit steps below. This is
not a whole-lab installer or a service remediation tool. It grants no
Hyper-V/cluster rights and requires neither Arc nor AMA.

## Components and contracts

- `HybridServerReadOnly` is a Windows PowerShell 5.1 module with three exported
  functions, an exact role capability, and an installer-generated `.pssc`.
  Its manifest explicitly loads CimCmdlets and System.ServiceProcess for the
  fixed internal providers; this does not expose arbitrary CIM/service commands
  to the JEA caller. Qualified NIC projection preserves bounds under JEA proxies.
- `New-HybridServerConfiguration.ps1` generates and validates that configuration
  without registration; offline tests exercise the same generator as installation.
- `Install-HybridServerReadOnly.ps1` creates the fixed `HybridServer.ReadOnly`
  **WSMan** endpoint, `NoLanguage`, empty general command/provider lists, and
  explicit role mapping to the supplied dedicated domain identity or group.
  Its virtual account belongs only to the new `HybridServerReaders` local group,
  not Administrators or Hyper-V Administrators. Domain controllers are refused.
- The private MCP registers `get_server_facts`, `get_server_service_state`,
  `get_server_events` **only when a nonempty validated `Servers` allowlist is
  configured**. Omitted/empty configuration preserves old discovery and calls.
  Only an opaque configured server ID is accepted, never a hostname, endpoint,
  credential, XPath, command or PowerShell script supplied by a caller.
- The executor uses the Windows MCP service's **integrated domain identity**
  with Kerberos, encryption, no redirects/fallback, and the fixed endpoint.
  This is independent of the LocalBox node credential and node readers.
  Use a dedicated nonadmin domain service account/gMSA; no password parameter,
  password file or credential forwarding is introduced here.
- Reads execute sequentially across all configured ordinary servers. Open:
  10 seconds; command: 15 seconds; caller wait: 30 seconds; transport: 256 KiB;
  accepted JSON: 128 KiB. Cancellation requests stop; the execution gate stays
  held until native disposal completes. Subsequent calls cannot pile up.

| Tool | Exact arguments | Bounds / evidence |
|---|---|---|
| `get_server_facts` | `target` | Hostname/UUID; OS/current memory; 16 NICs and disks; 8 CPUs/current load |
| `get_server_service_state` | `target`, `service: "Spooler"` | One service state, no start/stop |
| `get_server_events` | `target`, `log`, `maxCount`, `lookbackMinutes` | System/Application only; 1–50 records; 1–1440 minutes |

Facts use local CIM queries (3-second operation limit each); NIC address lists
are capped at eight entries and strings are bounded. Events query one extra
record to indicate truncation; messages are capped at 1,024 characters.
No matching events is a successful empty observation, **not evidence of health**.
Provider errors are `denied`/`unknown`, never healthy empty observations.
Outer status is unknown if any provider is incomplete. Every result carries
server-generated correlation, UTC timestamps and connecting/execution identity.
Transport/contract failures return bounded error codes without exception text.
CPU is a provider's current observation, not a benchmark or historical average.

## Setup (operator actions; not executed by source validation)

For a fresh attendee environment, start with [domain/KDS/gMSA preparation and
service-logon policy](../../docs/guest-setup.md). The [broker installation guide](../../docs/mcp-service-install.md)
covers publishing and Windows service registration; neither is done by this installer.

1. Select a noncritical ordinary, domain-joined Windows server. Independently
   validate private DNS/WSMan reachability, SPNs, firewall scope and the dedicated
   service identity. Do not enable Basic, TrustedHosts, CredSSP, SSH or public
   RDP forwarding. Enable/configure WSMan separately under your change process.
2. Copy this folder to the guest. Review the three scripts and module, then
   preview and install from **elevated Windows PowerShell 5.1**:

   ```powershell
   .\Install-HybridServerReadOnly.ps1 -CallerIdentity 'EXAMPLE\mcpRead$' -WhatIf
   .\Install-HybridServerReadOnly.ps1 -CallerIdentity 'EXAMPLE\mcpRead$'
   ```

   The identity may be a dedicated group; never use a broad builtin group.
   No directory account, group memberships or provider permissions are created.
    `RestrictedRemoteServer` retains PowerShell's standard JEA infrastructure
    commands (such as `Get-Command`/`Exit-PSSession`); no general provider or
    arbitrary command access is added.
   Existing endpoints/groups/files cause a collision error, not overwrite.
   Schedule a WinRM restart separately; the installer deliberately does not
   disrupt existing remoting sessions. Failed partial installation is retained
   for operator inspection; do not blindly delete or rerun it.

3. Validate **effective local provider permissions**, which are intentionally
   not elevated by installation:
   - CIM: ordinary local authenticated-user `root\cimv2` read/Enable Account
     permissions on the listed Win32 classes. No Remote Enable is necessary:
     CIM executes locally inside JEA, not remotely using caller credentials.
   - SCM: local connect and Spooler query-status access only. Standard Windows
     ACLs commonly permit these reads; hardened servers can deny them. Start,
     stop, change-config and service repair permissions are neither needed nor
     granted. The function opens a fixed `ServiceController('Spooler')` rather
     than enumerating all services. See the official
     [SCM/service access-rights reference](https://learn.microsoft.com/windows/win32/services/service-security-and-access-rights).
   - System/Application: channel **read** access for the virtual execution
     identity. Inspect each channel's `channelAccess` security descriptor.
     If baseline ACLs deny reads, a security owner must separately approve an
     additive channel read (`0x1`) ACE for the newly created runtime group's SID
     on those two channels only. Preserve original ACLs and record your ACEs
     for independent rollback. Do not add Event Log Readers (which would grant
     broader log access), Security-log privileges, admin membership or broad
     WMI/SCM rights just to make the demo green.

   This package deliberately changes **no provider ACLs**. Denied reads are a
   valid diagnostic result, but successful NIC/disk/event reads still require
   guest acceptance. Removing this package does not remove separately approved
   provider grants; the operator who owns those grants must remove exactly
   their recorded ACEs before deleting the runtime group.

4. As the actual MCP service identity, run the identity/read and negative probe:

   ```powershell
   .\Test-HybridServerReadOnly.ps1 -ComputerName server01.example.test `
       -ExpectedMachine SERVER01 -ExpectedCaller 'EXAMPLE\mcpRead$'
   ```

   This creates a Kerberos session, verifies identity/correlation/nonadmin
   execution, reads Spooler/events, rejects an unlisted service/log, excessive
   count/window, `Get-Service`, direct/qualified arbitrary CIM and host parameters, then closes the
   session. It makes no configuration changes. Inspect all provider statuses;
   passing identity/negative tests alone is not complete data-access proof.
   A gMSA is not an interactive login: do not run this as the installer and
   claim gMSA acceptance. Use the [actual service-identity testing path](../../docs/guest-setup.md#testing-as-the-actual-gmsa);
   a separate owner-approved launcher is needed for the full script under a gMSA.

5. On the approved **domain-joined MCP host** merge the dummy `Servers` array from
   `..\private-mcp\servers.example.json` into the protected `boundary.local.json`,
   substituting independently approved values. Run that service under its
   approved nonadmin domain runtime identity. Do not switch the shared WORKGROUP
   LocalBox-Client service identity, reuse node credentials or widen node access;
   use a separate domain-joined service host when the existing host is WORKGROUP.

   Set explicit listener/source policy and `HostTarget` as documented by the
   [portable boundary source](../private-mcp/README.md); retain exact TLS/caller/
   `LocalBox.Diagnostics.Read` checks. Host provisioning, certificates, network
   controls and managed service identities remain separately reviewed operator
   responsibilities; copying dummy JSON is not a standalone boundary installer.

6. Use the already authenticated native MCP connector to discover the three
   tools and call, for example:

   ```json
   {"name":"get_server_events","arguments":{"target":"server-01","log":"System","maxCount":5,"lookbackMinutes":60}}
   ```

   Verify server-generated correlation in native tool trace/result and the
   boundary's metadata-only audit. Probe missing/incorrect caller tokens,
   unknown server IDs and extra `command` arguments; none may reach JEA.
   Capture only redacted evidence. Event messages, host UUIDs, NIC addresses,
   domain identities and native tool results are private operational data:
   **never commit/publish raw logs or paste them into public reports**.

## Offline validation and teardown

```powershell
pwsh -NoProfile -File .\Test-Offline.ps1
powershell.exe -NoProfile -File .\Test-Offline.ps1
dotnet test ..\private-mcp\tests\PrivateMcp.Tests.csproj --no-restore
```

The offline script parses all assets, validates the manifest, executes bounded
provider/failure/text tests and rejects invalid parameters without touching
Windows providers. .NET tests exercise actual authenticated MCP protocol with a
fake executor, not just source regex. They also preserve the LocalBox suite.

Disable by removing the `Servers` configuration and restarting the boundary.
After sessions have ended and independently owned provider grants have been
rolled back, use elevated Windows PowerShell on the guest:

```powershell
.\Remove-HybridServerReadOnly.ps1 -WhatIf
.\Remove-HybridServerReadOnly.ps1
```

Removal requires matching ownership marker, group SID/description, empty group,
unchanged file hashes, no extra files/reparse points and matching registered
endpoint identity, path and SHA-256.
The Windows group description uses a short `HybridJEA:<GUID>` marker within
the 48-character limit; the receipt retains the full installation Owner and exact
GroupDescription. Removal also understands receipts using the original Owner
description, without relaxing SID or ownership validation.

Windows PowerShell 5.1 copies the source
PSSC into its SessionConfig directory: the installer records the **actual**
registered path only after registration succeeds and the copy matches the
source hash and per-installation configuration GUID. The protected version-2
receipt also binds the source to the expected nonadmin JEA setup, caller role,
module and initialization paths; a copied path alone is not proof of ownership.
The receipt is administrator-owned evidence, not a defense against a malicious
administrator who can replace both the receipt and installation.

A pre-registration `Pending` receipt permits cleanup of unchanged owned files
and the empty owned group only when no endpoint exists. If registration throws
after creating an endpoint, post-registration verification fails, or receipt
writing is interrupted, cleanup refuses an unconfirmed endpoint. Retain those
resources for operator inspection; do not infer ownership or broadly delete.
Failures before the receipt exists and older receipts require manual review.
Only Unregister-PSSessionConfiguration handles its registered copy; cleanup
never recursively deletes the shared SessionConfig directory.

Both offline runtimes execute production installer/remover logic with fake
registration, group and ACL cmdlets in repository-local scratch directories.
Tests cover copied-path round trips, receipt/path/hash/GUID/setup tampering,
foreign files/directories/group members, WhatIf, and registration failures
before and after endpoint creation. No live endpoint is registered.

Drift stops removal for human review. It does not erase foreign
memberships/grants or restart WinRM. Schedule restart separately.

Live acceptance still requires installed-guest JEA discovery, effective token
inspection, all required provider reads, denied commands, timeouts/cancellation,
native agent correlation, teardown and revalidation of unchanged LocalBox
denials. No live calls or installations were made in this increment.

References: [JEA session configuration](https://learn.microsoft.com/powershell/scripting/security/remoting/jea/session-configurations),
[JEA security considerations](https://learn.microsoft.com/powershell/scripting/security/remoting/jea/security-considerations),
[JEA role capabilities](https://learn.microsoft.com/powershell/scripting/security/remoting/jea/role-capabilities).
