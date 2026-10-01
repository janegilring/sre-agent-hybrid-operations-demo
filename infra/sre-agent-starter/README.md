# Azure SRE Agent attendee starter

A self-contained **new** SRE component, not an Azure
Local/LocalBox redeployment. Never point this at an existing/shared agent.
**Local compilation is not Azure service acceptance.** No subscription, region,
ARM validation, deployment, private connectivity or runtime behavior has been
certified by this package's offline tests.

## What this creates

In an **existing attendee-supplied resource group**, `main.bicep` creates an SRE
Agent, a user-assigned identity, a 30-day Log Analytics workspace and workspace-
based Application Insights. The agent also has a system-assigned identity.
Current typed API: `Microsoft.App/agents@2026-01-01`; action configuration is
`accessLevel: Low`, `mode: ReadOnly` (not a made-up `Reader` action mode).
The UAMI is the action/knowledge-graph identity. Existing managed resource groups
are selected by name within the explicit deployment subscription.

**Private access is NOT configured. Not usable for private-server investigations
until networking and authenticated tools are configured and tested.** Default
product egress is Unrestricted, not private isolation. Do not connect sensitive
data or tools until the network review is complete.

### Permission boundaries

- `grantTargetReader=false` by default. Setting it true grants only **Reader**
  to the new UAMI, directly on each exact `targetResourceGroupNames` entry.
  Selecting managed resources alone is not a permission grant.
- `agentAccessUserObjectIds=[]` by default. Optional approved, nonempty Entra
  **user object IDs** receive Reader and SRE Agent Administrator on the new
  agent only. No automatic current-user/deployer or managed-identity admin grant.
  Leave empty only if an administrator will arrange user access separately.
- No workload Contributor, Owner, Monitoring Contributor, subscription-wide
  grants, provider registration, or role-assignment cleanup outside the owned set.
- The official template also uses **Monitoring Reader** on the agent deployment
  RG and **Log Analytics Reader** on target RGs, including the system identity
  used for connector queries. This starter deliberately does **not** silently
  install these additional grants. Have an administrator review each connector's
  actual identity and effective access, then grant only on the specific workspace,
  telemetry resource or approved RG required. Reader-only discovery must not be
  represented as complete log/connector functionality.
- Provisioning requires resource-write/deployment permissions on the deployment
  RG and UAMI assignment permission. Opt-in roles additionally require
  `Microsoft.Authorization/roleAssignments/write` at their exact scopes; nested
  target deployments require deployment permissions at target RGs. Cleanup
  requires corresponding delete permissions. The official end-to-end quickstart
  lists subscription Owner or Contributor + User Access Administrator; this
  starter does not grant either to anyone or promise narrower custom roles work
  without administrator validation.

## Portal-first quickstart

1. Sign in to the Azure portal with an approved attendee identity. Search for
   **Azure SRE Agent**, start creation, select your subscription, existing RG,
   supported region and a **new unique name**.
2. Review identity and managed-resource selections; select only approved RGs.
   Review the actual wizard-generated role assignments. Cancel if it requests
   broader access than approved; use this explicit IaC route instead.
3. Review pricing, preview/offer availability, policy and permissions before
   Create. For a demonstration walkthrough, stop at review without submitting.
4. After approved creation, inspect actual identities and inherited RBAC.
   Configure user access, network and connectors separately as below.
5. Use a harmless read-only prompt against one approved resource and require
   current evidence and explicit unknowns. Do not start schedules or incidents
   merely to prove provisioning.

## IaC interface (PowerShell 7.2+, installed Bicep and Azure CLI)

No auto-installs. Authenticate separately; every Azure operation takes an explicit
subscription. Scripts never run `az account set`. Use a new output directory
inside this component; receipts contain tenant-specific IDs and are gitignored.

```powershell
Set-Location infra\sre-agent-starter
New-Item -ItemType Directory .local -Force | Out-Null
Copy-Item parameters.example.json .local\parameters.local.json
# Edit agentName, location, targetResourceGroupNames and approved opt-ins.
# ownershipToken is a sample placeholder; Deploy generates a fresh token.
$subscriptionId = '<attendee-subscription-guid>'
$resourceGroup = 'rg-attendee-agent'

.\Test-Contracts.ps1
.\Test-Regression.ps1
.\Validate.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ParametersFile .local\parameters.local.json -LocalOnly

# Read-only Azure checks: target existence, no overwrite, provider/API,
# ARM validation and what-if. Review the complete change list.
.\Validate.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ParametersFile .local\parameters.local.json

# Separate, explicitly approved mutation; SupportsShouldProcess/-WhatIf.
.\Deploy.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ParametersFile .local\parameters.local.json `
  -ManifestPath .local\owned.local.json -Apply

# Preview exact ownership-checked cleanup first, then approve deletion.
.\Cleanup.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ManifestPath .local\owned.local.json
.\Cleanup.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ManifestPath .local\owned.local.json -Apply
```

`main.example.bicepparam` is an alternative parameter format; copy it beside
`main.bicep` as `main.local.bicepparam` (its relative `using` must stay correct).
The wrappers accept either format and reject missing/invalid inputs. Deploy
creates a manifest before ARM execution, refuses existing resource names and
existing receipts, and is **create-only**, not an update tool. Do not bypass
the wrappers for shared resources. Serialize deployment with other operators:
the read-before-create check is not an atomic resource-name reservation.

Cleanup checks explicit subscription/RG, expected resource IDs, ownership tags,
role descriptions, exact role scopes and principals. It handles partial
deployments, retains deployment history, and never deletes RGs, target workload
resources or externally granted roles. Keep the receipt private and unmodified.
Deleting the agent also removes its child configuration; export approved
configuration first. A changed/missing ownership tag stops cleanup.

Cleanup enumerates each target/deployment RG and the agent resource separately,
using exact-scope CLI listing (without `--all` or inherited assignments).
The regression suite exercises subnet responses with omitted optional fields,
mocked cleanup including post-delete checks, and the installed Azure CLI's real
role-list validator and filtering against SDK-paged offline responses. It makes
no Azure/authentication calls or user-profile changes. On non-MSI installations,
pass `-AzureCliPython` pointing to a Python executable with Azure CLI installed.

## Native network: separate reviewed configuration

The current typed agent schema does **not** expose the older preview template's
`vnetConfiguration`/`sandboxConfiguration`. They are intentionally not invented
here or injected through untyped JSON. Use **Settings > Workspace configuration
> Network > Azure VNet**, browse an **existing dedicated** same-region subnet
delegated to `Microsoft.App/environments`, IPv4 `/27` or larger, and Save after
network-owner approval.

Optional read-only preflight:

```powershell
.\Validate.ps1 -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup `
  -ParametersFile .local\parameters.local.json `
  -ExistingSubnetResourceId '<full-approved-subnet-resource-id>'
```

This checks region, delegation, prefix and visible allocations, **not** routing,
DNS, service association, available capacity or dedicated ownership. It does
not attach/change/create the subnet. Verify VPN/ExpressRoute/private routing,
DNS, firewall and NSG separately, and keep MCP infra-network bypass disabled
for the intended private route. Current docs say connector traffic uses the
public internet and inbound private endpoints are unsupported: do not claim
all connector traffic becomes private with VNet mode.

## Native configuration / OAuth: deliberately unfinished

Bicep provisions the core ARM resources only. No invented agent YAML is shipped.
The official IaC path distinguishes `agent.json`, `connectors.json`, `roles.yaml`,
native skills/subagents/hooks and ARM extensions from data-plane operations.
Hooks, repository authentication, HTTP triggers, binary knowledge and plugin
configuration have separate data-plane steps. YAML assets are **future work,
not completed** by this starter.

For a reviewed attendee agent, pin the official `microsoft/sre-agent` repository
to a reviewed commit, inspect that revision's README and export command help,
then export **only your approved new agent** to a private working directory.
Record the commit/API versions with the export, inspect generated native files
and validate with that same revision's supported tooling before importing.
Do not clone/export shared production agents, secrets or private bindings.
This package consulted revision
`25a42306d298c4d28f11dd11ef9bb93cb0393be8`; its template uses an older
`2025-05-01-preview` API and contains preview fields not present in the current
typed API. Do not copy those fields or its broader roles into this starter.

Manually authorize approved GitHub/Azure DevOps repository access (OAuth/PAT
as supported), Teams/Outlook and any incident/managed connector accounts using
the product UI. Supply connector-specific credentials only through approved
secret handling. Verify principal, consent, scope and token refresh; neither
ARM success nor a managed identity completes third-party OAuth. Do not enable
schedules, webhooks or response plans before separate acceptance.

## Acceptance, preview and cost gates

- Confirm the product's current preview/offer terms and supported **subscription
  and region**; no region default is a promise of availability. Read-only ARM
  validation and what-if are mandatory before apply and may still not expose
  capacity/provisioning failures.
- Review [pricing](https://azure.microsoft.com/pricing/details/sre-agent/)
  and your agreement. Agent operation, telemetry ingestion/retention, networking
  and connected services can incur charges; this is **not a free lab**.
  Workspace retention is 30 days; no budget, agent-unit cap, data deletion
  guarantee or connector retention policy is implied.
- Verify provisioning state and resource IDs; verify user login, both identities,
  effective RBAC, managed RG scope, ReadOnly mode and logs; then prove private
  connectivity with a bounded read-only tool result.
- Do not promise an end-to-end demo until those checks and approved native
  configuration/OAuth steps have succeeded.

## Authoritative sources checked 2026-10-01

- [Deployment and ARM/data-plane boundary](https://learn.microsoft.com/azure/sre-agent/deploy-iac)
- [Current agent resource/API schema](https://learn.microsoft.com/azure/templates/microsoft.app/agents)
- [Network modes and limitations](https://learn.microsoft.com/azure/sre-agent/network-integration)
- [User permissions](https://learn.microsoft.com/azure/sre-agent/setup-mcp-server#assign-permissions-for-sre-agent)
- [Official pinned core template](https://github.com/microsoft/sre-agent/blob/25a42306d298c4d28f11dd11ef9bb93cb0393be8/sreagent-templates/bicep/agent-core.bicep)
- [Official pinned target roles](https://github.com/microsoft/sre-agent/blob/25a42306d298c4d28f11dd11ef9bb93cb0393be8/sreagent-templates/bicep/role-assignments-target.bicep)

This is an independently authored minimal component, not a copy of the
official deployment framework or a claim of runtime certification.
