# Spooler-only JEA recovery (offline implementation)

Independent of `hybrid-server` and the private MCP server. **Not installed,
not connected to SRE, and not evidence of native approval or live recovery.**
No Azure Local prerequisite. Target: one explicitly approved noncritical Windows
guest with Spooler installed and not disabled by security policy. No fault
injection or stop/restart automation is included.

## Contract

* `Get-HybridSpoolerState`: fixed local service, fresh UTC observation, disabled
  flag and positive `RunningVerified`.
* `Start-HybridSpooler [-TimeoutSeconds 1..60]`: default 15 seconds, idempotent
  Running no-op, refuses disabled/paused/stopping/unknown states, waits for an
  existing start, never changes startup type. No service name, hostname or
  service arguments accepted. `-WhatIf` returns `Planned / NotExecuted`, never
  an action-success result. A successful action requires fresh Running.
* Errors terminate with `HybridSpoolerRecoveryFailed`; the error's
  `TargetObject` contains outcome, state, verification, timestamps, duration
  and error. Timeout means **verification pending**, not repaired. An already
  issued Windows start request may complete later and cannot safely be
  cancelled. Inspect before retry. Start's deadline covers initial query,
  action and verification, excluding module compilation and confirmation time;
  the standalone read has a five-second deadline. Poll scheduling can add up
  to 100 ms. Native SCM calls run on .NET tasks so a blocked `StartService` or
  query does not hold the polling deadline.
* JEA exposes only the two fixed functions (plus standard restricted-session
  plumbing); reader capability exposes only the state function. Runtime uses
  the new custom local group **only**, not Administrators.

## Future authorized installation

Use **64-bit Windows PowerShell 5.1 as administrator**, locally on the selected
guest, after owner review. No target parameter or remote install exists.
The installer does not grant any SRE caller access unless an operator explicitly
supplies that identity: **do not supply it until the native approval gate below
has passed**. Initially use a dedicated human demonstration operator.

```powershell
.\Install-HybridSpoolerRecovery.ps1 -CallerIdentity 'EXAMPLE\demo-operator' -WhatIf
.\Install-HybridSpoolerRecovery.ps1 -CallerIdentity 'EXAMPLE\demo-operator'
# Optional distinct dedicated read caller: -ReaderIdentity 'EXAMPLE\demo-reader'
```

This creates `HybridSpoolerRecovery`, a generated NoLanguage PSSC, explicit
caller-to-role mappings, a caller-only execute ACL (SYSTEM/administrators retain
management access), protected module files and `HybridSpoolerOperators`.
Name collisions fail before mutation; it never re-registers a foreign endpoint.
Domain controllers and built-in/broad caller SIDs are refused. Operators must
also verify that chosen custom groups are narrowly populated.

The only added **service** ACE is Allow / no inheritance / new group SID /
`0x15`: `SERVICE_QUERY_CONFIG (1) | SERVICE_QUERY_STATUS (4) | SERVICE_START (16)`.
Neither INTERROGATE nor STOP/CHANGE_CONFIG/WRITE_DAC is needed at runtime.
SCM is opened with CONNECT only, using its existing local authenticated access;
no SCM DACL is broadened. Existing service ACEs are preserved, not sanitized.
Windows may start normal dependencies as part of starting Spooler; no dependency
control operation is exposed. Review dependency baseline before authorizing.

No WinRM restart is performed. Schedule activation yourself; existing sessions
can survive configuration changes. In that approved window validate actual
nonadmin token membership, role visibility, denied arbitrary commands/services,
read-only caller denial of Start, and positive healthy state. Then an approved
operator can invoke **exactly** `Start-HybridSpooler` through this endpoint in a
JEA session. There is no built-in per-invocation human approval broker: endpoint
authorization and PowerShell ShouldProcess are not SRE approval.

## Ownership and removal

`C:\ProgramData\HybridSpoolerRecovery\Ownership.json` records the resource,
group SID, exact rights, before/after DACL text and hashes, module/source hashes,
configuration GUID, and **actual registered** ConfigFilePath/hash/GUID.
Windows PowerShell 5.1 can copy the PSSC; cleanup compares the registered copy,
not its path with the source. This is the small source/copy ownership pattern
used by `..\hybrid-server\Ownership.ps1`, without a runtime dependency or changes
to that component.

```powershell
.\Remove-HybridSpoolerRecovery.ps1 -WhatIf
.\Remove-HybridSpoolerRecovery.ps1
```

Cleanup refuses changed files/group membership/registration and service-DACL
drift, removes only the exact-owned ACE, and never restores an old DACL over
observed foreign changes. The helper rechecks immediately before writing and
verifies afterward; `sc.exe sdset` has **no atomic compare-and-swap**. Serialize
other administrative service-ACL writers during installation/removal; a truly
concurrent write in the OS race window cannot be made transactional. On any
postcondition failure retain the receipt and inspect; do not blindly retry or
restore a snapshot. Pending registrations can be identified using the source
hash and GUID even after a registration interruption. Failures before receipt
creation require operator inspection of the uniquely marked group/directories.
Drain active sessions before removing resources. No service state is changed
by either installation or cleanup.

## Offline validation

```powershell
powershell.exe -NoProfile -File .\Test-Offline.ps1
pwsh.exe -NoProfile -File .\Test-Offline.ps1
powershell.exe -NoProfile -File .\Test-InstallerOffline.ps1
pwsh.exe -NoProfile -File .\Test-InstallerOffline.ps1
```

No dependencies. Tests compile native interop without calling it; replace every
runtime service seam; execute actual public functions against stubs; verify
timeouts, errors, WhatIf, malicious parameters, DACL ownership/drift, generated
PSSC and registered-copy hashes/GUIDs. The installer lifecycle suite substitutes
host/identity preflight and all system mutation commands, then executes the
real receipt/configuration/cleanup bodies against workspace-only scratch files.
Installation and removal are **not** executed against the machine.
Actual JEA token/service authorization and platform
behavior remain a separately approved lab validation, not an offline claim.

## Native SRE integration remains blocked

No MCP tool, connector, agent configuration or routing is changed here.
A future fixed tool must be annotated **`readOnlyHint: false`**; that annotation
is advisory metadata, **not a security or approval boundary**. Before granting
an SRE caller endpoint access or adding the tool, separately prove the native
Review-mode custom-write flow blocks execution until a human approves, including
denial, cancellation, timeout and replay behavior. Retain auditable correlation
between approved target/action, caller, request and fresh positive verification.
Never replace that evidence with an `approval=true` argument.

Intentional interruption needs fresh owner approval, target/baseline/recovery
access, telemetry and rollback gates. No interruption is authorized by these
assets. Service-state collection, real incident routing, native tool execution,
automatic final Teams response and positive telemetry recovery remain pending.

## First-party implementation references

[service access rights](https://learn.microsoft.com/windows/win32/services/service-security-and-access-rights),
[Win32 DACL merge example](https://learn.microsoft.com/windows/win32/services/modifying-the-dacl-for-a-service),
[StartService blocking behavior](https://learn.microsoft.com/windows/win32/api/winsvc/nf-winsvc-startservicew),
[JEA configuration and nonadmin virtual account groups](https://learn.microsoft.com/powershell/scripting/security/remoting/jea/session-configurations),
[JEA endpoint ACLs](https://learn.microsoft.com/powershell/scripting/security/remoting/jea/security-considerations).
The sample's broad Guest permissions are deliberately **not** reproduced.
