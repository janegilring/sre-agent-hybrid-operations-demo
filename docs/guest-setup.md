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

## Operator sequence

1. Select one noncritical **domain-joined member server** and a dedicated
   nonadmin caller. Verify AD DNS, SPNs, time and encrypted WSMan reachability.
   Do not enable Basic, CredSSP, TrustedHosts or public guest forwarding.
2. Review [JEA setup](../tools/hybrid-server/README.md). Run its offline tests.
   Preview installation with `-WhatIf` before separately approving registration.
   The installer does not grant broad provider ACLs or restart WinRM.
3. Review and build the [complete MCP source](../tools/private-mcp/README.md).
   Start with its documentation-only `boundary.example.json` and
   `servers.example.json`; unchanged identity placeholders fail validation.
   Use a protected private configuration, not committed account bindings.
4. Keep node identity/read capabilities disabled for ordinary servers.
   Configure exactly one opaque server ID, approved FQDN and expected machine/
   connecting identity. Callers supply that ID, not arbitrary endpoints.
5. Provision your service identity, TLS certificate/private-key access and
   narrowly scoped network rules under your own change process. If using a
   gMSA, AD manages the password. No password file or identity reuse is required.
6. Verify tool discovery and sequential facts, Spooler query and bounded events.
   Correlate native calls with the backend audit. Check connecting **and**
   execution identity. Deny another target, arbitrary commands and service writes.
7. Verify empty, denied, stale and timed-out results remain explicit.
   An empty event sample is not healthy; transport success is not provider success.
8. Record certificate ownership/expiry and a tested replacement procedure.
   A documented renewal task is not evidence that replacement has succeeded.

## What is not installed by this guide

No Arc/AMA requirement for guest reads, no automatic service repair, no node
administrator grant, no privileged collector, no native report or schedule.
The separate [Spooler Start-only source](../tools/hybrid-service-recovery/README.md)
is a distinct capability and authorization decision. Never add it merely to
make a read-only demo pass.

All source, projects, lockfiles, module manifests, role capability, installer/
remover ownership helpers and offline tests are included through the explicit
export allowlist. Lab-specific deployment/credential/certificate scripts are
deliberately excluded; the steps above make their manual replacement explicit.
