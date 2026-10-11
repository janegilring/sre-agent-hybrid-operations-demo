# Connect one ordinary Windows server safely

This is a reviewable integration checklist, not an unattended whole-lab
installer. Use your own approved identity, network, certificate and server
bindings. Never copy an operational environment's credentials or endpoints.

## Trust route

SRE Agent private outbound → optional private TCP forwarder → authenticated
MCP on a **domain-joined Windows host** → dedicated nonadmin domain service
account/gMSA → Kerberos → fixed `HybridServer.ReadOnly` endpoint on one guest.

The forwarder can be WORKGROUP; it does not authenticate to the guest.
TLS/Entra authentication terminate on the MCP backend. Configure the source
allowlist for the **actual observed packet source**, not an assumed forwarded
header. The upstream SRE connector needs approved private DNS/routing;
VNet integration does not imply all connector traffic follows that route.
Preserve any existing node runtime and its credentials as an independent path.

## Minimum environment and identities

Use one existing AD DS domain, a **separate domain-joined Windows broker** and
one noncritical domain-joined member server. A small lab therefore still needs
a DC/DNS service; this kit does not build a domain. Use supported, patched
Windows Server 2022/2025 x64 for a new broker, subject to current .NET 10 OS
support. The guest needs Windows PowerShell 5.1 and WinRM/JEA. Neither machine
needs Azure Local, LocalBox, Arc or AMA for this path.

| Actor | Where it acts | Rights, not interchangeable identities |
| --- | --- | --- |
| Directory owner | AD administration host/DC | Delegated gMSA object creation; KDS initialization separately requires domain/forest-level authority |
| Broker installer | Broker | Local administrator for files, certificate key ACL, Event Log source and SCM registration; never the runtime identity |
| Guest installer | Guest | Local administrator for the fixed JEA endpoint; provider grants are separately approved |
| `EXAMPLE\mcpRead$` (sample gMSA) | Broker service -> guest | Nonadmin service logon on broker, exact JEA caller mapping on guest |
| JEA virtual account | Inside the guest endpoint | Only `HybridServerReaders`; provider reads, not Administrators |
| Entra application caller | HTTPS MCP boundary | Exact tenant/audience/client/object/role checks; not an AD account or Windows logon |

Replace `EXAMPLE`, `example.test`, `MCP01`, `SERVER01` and `mcpRead` throughout
with your own reviewed names. Sample `.test` DNS names are documentation-only;
the TLS name must be resolvable and trusted by the actual client. Do not put
real bindings or operational receipts in Git.

## Create and install the gMSA

These are **manual, separately approved AD/host changes**, not commands run by
the offline tests. A gMSA is a service identity, not an interactive account:
do not use `runas`, RDP, `Get-Credential`, a password file or password extraction.
An Azure managed identity cannot replace this AD/Kerberos identity.

### Directory prerequisites and KDS gate

The directory owner must confirm a healthy AD DS domain/forest at Windows
Server 2012 functional level or later, supported DCs, working replication,
AES-compatible Kerberos policy, correct DNS and synchronized clocks.
Use 64-bit Windows PowerShell 5.1 with the ActiveDirectory module (RSAT).
The broker and guest must already be joined to this domain. Do not install
AD DS on the broker to obtain management cmdlets.

On an authorized DC, inspect **metadata only** for existing KDS keys:

```powershell
Import-Module Kds -ErrorAction Stop
Get-KdsRootKey | Select-Object KeyId, CreationTime, EffectiveTime
```

Reuse an established usable root key. If none exists, stop and obtain the
directory owner's explicit approval for this **forest-wide prerequisite**.
Only that owner, on the DC, runs the following once:

```powershell
Add-KdsRootKey -EffectiveImmediately
```

Despite its name, do not proceed immediately in a multi-DC environment. Allow
**at least ten hours and successful replication to every relevant DC**;
restricted replication schedules or errors can require longer. Verify KdsSvc
Operational event 4004 and replication health. Never recreate/delete an
existing KDS key to repair this demo.

Microsoft documents backdating a root key only for an isolated **single-DC
test forest**. That shortcut is not needed for this guide and is deliberately
not a runnable step here. It is not safe advice for production, a multi-DC
lab, or a domain whose topology you do not own.

### Authorize only the broker to retrieve the password

After the KDS gate, run on the AD administration host with delegated creation
rights. The direct computer authorization below is intentionally narrower
than `Domain Computers`; the guest and TCP forwarder must not retrieve the
password. Have the directory owner confirm the account name is forest-unique.
The OU must already exist and be approved.

```powershell
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$gmsaName = 'mcpRead'
$brokerName = 'MCP01'
$accountOu = 'OU=Service Accounts,DC=example,DC=test'
$broker = Get-ADComputer -Identity $brokerName
Get-ADOrganizationalUnit -Identity $accountOu | Out-Null
if (Get-ADObject -LDAPFilter "(sAMAccountName=$gmsaName`$)") {
    throw 'Account collision: do not adopt or overwrite an existing account.'
}
$newAccount = @{
    Name = $gmsaName
    DNSHostName = 'mcpRead.example.test'
    Path = $accountOu
    KerberosEncryptionType = @('AES128', 'AES256')
    PrincipalsAllowedToRetrieveManagedPassword = $broker
    Description = 'Dedicated attendee MCP read-only broker identity'
}
New-ADServiceAccount @newAccount -WhatIf
# After reviewing the exact account, OU and broker:
New-ADServiceAccount @newAccount
Get-ADServiceAccount -Identity $gmsaName `
    -Properties PrincipalsAllowedToRetrieveManagedPassword, KerberosEncryptionType |
    Select-Object Name, SID, ObjectGUID, DistinguishedName,
        PrincipalsAllowedToRetrieveManagedPassword, KerberosEncryptionType
```

Keep that object identity and authorization as a private ownership record.
Do not query `msDS-ManagedPassword` or use `-Properties *`. No inbound Kerberos
SPN is registered on the gMSA: MCP accepts Entra JWTs over TLS, while this
account is an **outbound** Kerberos client to the guest's existing WinRM SPN.
Never move the guest's HTTP/HOST SPNs onto this service account.

A dedicated host security group is an alternative for multiple brokers, not
required here. If an owner chooses it, record exact computer membership and
account retrieval authorization; wait for AD replication and refresh the
broker's computer token in an approved maintenance window before testing.
Do not add users, guests, forwarders or broad/nested groups to make a test pass.

### Install on the broker, not the guest

Use elevated Windows PowerShell 5.1 on the approved broker. If the AD module is
missing, a host owner can separately install the RSAT AD PowerShell feature
with `Install-WindowsFeature RSAT-AD-PowerShell`; review any restart requirement.
This does not create a domain or grant runtime privileges.

```powershell
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Install-ADServiceAccount -Identity 'mcpRead'
if (-not (Test-ADServiceAccount -Identity 'mcpRead')) {
    throw 'gMSA not usable on this broker. Stop before registering the service.'
}
```

`True` proves local gMSA usability, **not** JEA authorization, provider access,
service-logon policy, TLS key access or SRE connectivity. On failure, inspect
DNS/time/DC reachability, KDS replication/age, exact retrieval authorization
and Kerberos policy with the directory owner. Do not fall back to a password,
NTLM, LocalSystem or an administrator account.

### Effective service-logon and runtime rights

On the **broker only**, the policy owner grants `EXAMPLE\mcpRead$` **Log on as a
service** (`SeServiceLogonRight`) at Computer Configuration -> Windows Settings
-> Security Settings -> Local Policies -> User Rights Assignment. Use a
broker-scoped GPO if domain policy controls it; otherwise use `secpol.msc`.
Preserve every existing entry. User-rights lists in GPO replace lower-precedence
lists; a local edit that will be overwritten is not a solution.

Inspect the resultant computer policy (`rsop.msc` or `gpresult /scope computer /r`)
and **Deny log on as a service**, including inherited group membership. A deny
overrides an allow. Do not remove a security baseline deny without its owner's
review. Policy takes effect at the next service logon; no forced reboot or
implicit service restart is part of these instructions.

The gMSA must not be a direct or nested member of local/domain Administrators,
Domain Admins, Hyper-V Administrators or other privileged runtime groups.
No interactive/RDP/batch logon, delegation, guest local-admin membership or
certificate-store-wide grant is needed. Actual nonadmin service startup and
guest connecting/execution identity must still be verified below.

## Operator sequence after identity preparation

1. Select one noncritical **domain-joined member server** and a dedicated
   nonadmin caller. Verify AD DNS, SPNs, time and encrypted WSMan reachability.
   Do not enable Basic, CredSSP, TrustedHosts or public guest forwarding.
2. Review [JEA setup](../tools/hybrid-server/README.md). Run its offline tests.
   Preview installation with `-WhatIf` before separately approving registration.
   The installer does not grant broad provider ACLs or restart WinRM.
3. Review and build the [complete MCP source](../tools/private-mcp/README.md).
   Follow [publish, protected installation, SCM registration and first
   start](mcp-service-install.md); `AddWindowsService` alone does not register
   a Windows service.
   Start with its documentation-only `boundary.example.json` and
   `servers.example.json`; unchanged identity placeholders fail validation.
   Use a protected private configuration, not committed account bindings.
4. Keep node identity/read capabilities disabled for ordinary servers.
   Configure exactly one opaque server ID, approved FQDN and expected machine/
   connecting identity. Callers supply that ID, not arbitrary endpoints.
5. Complete the service-logon, TLS/private-key and network gates in the
   installation guide. The current executor connects to the guest FQDN on
   **TCP 5985 with Kerberos message encryption**, not HTTPS/5986. Do not enable
   unencrypted WinRM or assume a 5986-only listener is supported by this source.
   Restrict guest inbound WSMan to the broker and use the real domain FQDN,
   not an IP/alias that lacks the correct SPN.
6. Verify tool discovery and sequential facts, Spooler query and bounded events.
   Correlate native calls with the backend audit. Check connecting **and**
   execution identity. Deny another target, arbitrary commands and service writes.
7. Verify empty, denied, stale and timed-out results remain explicit.
   An empty event sample is not healthy; transport success is not provider success.
8. Record certificate ownership/expiry and a tested replacement procedure.
   A documented renewal task is not evidence that replacement has succeeded.

### Testing as the actual gMSA

The JEA guide's `Test-HybridServerReadOnly.ps1` is an identity-sensitive probe.
Running it in the installer's admin console tests the **wrong caller** and is
not gMSA acceptance. This kit does not supply a scheduled-task or impersonation
launcher for that probe. Do not grant interactive logon or retrieve the gMSA
password to launch it.

For the gMSA route, use the registered broker service and an independently
approved authenticated MCP client to issue the three fixed reads. The compiled
reader checks expected machine, exact connecting identity, nonadmin JEA virtual
execution identity, source times and each provider contract on every result.
Use the [service acceptance checklist](mcp-service-install.md#acceptance-and-troubleshooting).
A separate owner-managed process under the gMSA can run the full JEA negative
probe if approved; until that is done, record that live negative-probe gate as
open. Offline negative tests are not a replacement for deployed-endpoint tests.

## Scoped teardown

First remove only your native connector/tool assignments, drain calls, and
[unregister your broker service](mcp-service-install.md#rollback-and-uninstall).
Roll back only separately recorded guest provider ACEs, then run the JEA
remover's ownership checks. Only after no service/task/endpoint consumes this
gMSA, a broker owner can run:

```powershell
Uninstall-ADServiceAccount -Identity 'mcpRead' -WhatIf
# Repeat without -WhatIf only after consumer and ownership review.
```

That is local uninstallation, not AD account deletion. The directory owner
must compare the originally recorded SID/ObjectGUID/DN and retrieval
authorization before using `Remove-ADServiceAccount -Identity <recorded-DN>
-WhatIf`, then separately approve removal. Do not delete by a convenient
display name or reconstruct ownership from current state. Remove only the
service-logon entry/key ACE/firewall rule this installation added; preserve
pre-existing policy entries, certificates and other consumers. **Never delete
the KDS root key, domain, OU or broker computer account as demo cleanup.**

## What is not installed by this guide

No Arc/AMA requirement for guest reads, no automatic service repair, no node
administrator grant, no privileged collector, no native report or schedule.
The separate [Spooler Start-only source](../tools/hybrid-service-recovery/README.md)
is a distinct capability and authorization decision. Never add it merely to
make a read-only demo pass.

All source, projects, lockfiles, module manifests, role capability, installer/
remover ownership helpers and offline tests are included through the explicit
export allowlist. Lab-specific deployment/credential/certificate scripts are
deliberately excluded. This guide and the service installation guide are
original portable kit documentation, not exported operator scripts.

## First-party references

Reviewed October 11, 2026; documentation is not live acceptance:
[manage gMSAs](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/group-managed-service-accounts/group-managed-service-accounts/manage-group-managed-service-accounts),
[KDS timing and single-DC exception](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/group-managed-service-accounts/group-managed-service-accounts/create-the-key-distribution-services-kds-root-key),
[Log on as a service and GPO precedence](https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/log-on-as-a-service),
[WinRM security](https://learn.microsoft.com/powershell/scripting/security/remoting/winrm-security).
