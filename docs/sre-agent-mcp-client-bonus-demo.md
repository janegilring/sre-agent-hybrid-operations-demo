# Optional bonus: reach Azure SRE Agent from Copilot or Claude

Read an existing SRE Agent thread from a development assistant using Azure MCP
Server. **Client integration is not tested by this starter.** The setup below
is based on first-party documentation reviewed October 10, 2026; use an approved
client profile and verify startup, authentication and scoped reads yourself.

## The important direction

```text
Copilot / Claude
  -> local Azure MCP Server (MCP over stdio)
  -> existing Azure SRE Agent (authenticated HTTPS service API)
```

Microsoft calls this capability the **SRE Agent MCP server**, but its documented
client entry point is **Azure MCP Server**, not a public per-agent MCP URL.
Azure MCP Server discovers the agent endpoint through Azure Resource Graph
and proxies requests into its service API. [1]

This is the reverse of the main hybrid demonstration:

```text
SRE Agent -> configured private MCP connector -> bounded Windows/JEA reads
```

Do not register a connector to demonstrate the first direction. Do not use a
portal/chat URL, append `/mcp` to an agent hostname, or infer SSE support.
An HTTPS `*.azuresre.ai` endpoint is a service API endpoint; that alone does
not make it a directly connectable MCP transport.

Architecture/YAML/connector helpers are not proof of this connection. Some
require `srectl init` and operate as CLI authoring/management helpers. Likewise,
an available `azure-sreagent` router declaration is not proof that its MCP
process started or authenticated.

## Compatibility and limits

| Claim | Evidence / status on October 10 |
| --- | --- |
| Client-to-SRE integration exists in first-party documentation | Microsoft Learn explicitly documents Azure MCP Server, endpoint discovery, permissions, and Copilot/Claude clients. [1] |
| A published package contains the required read tools | Official release `Azure.Mcp.Server-3.0.0-beta.50`, published October 6, 19:50:40 UTC, links NPM `@azure/mcp` version `3.0.0-beta.50`. Its tagged source registers `sreagent` and `threads get`; the latter is annotated read-only and retrieves existing messages without running an investigation. [3][4] |
| This starter supplies a successfully connected client | **No.** Validate your own installation; a local process startup failure does not prove SRE service failure or diagnose permissions. |
| Copilot CLI / VS Code / Claude Code / Desktop end-to-end acceptance | **NOT tested.** Configurations below are derived from first-party setup/schema documentation and tagged source. |
| Direct remote per-agent MCP URL / OAuth client registration | **Not established by the reviewed sources.** No invented URL, OAuth scope, API key, or bearer-header configuration is supplied. |
| Current health or recovery of your target guests | **Not assessed here.** Reading a historical thread would not prove current guest state or successful recovery. Substitute your reviewed targets in the prompts below. |

Treat the Azure package's **beta** designation and SRE preview API as explicit
compatibility limits. Pin the reviewed package; validate a newer version before
upgrading. The repository's global “latest release” can refer to another MCP
server, so use the Azure-specific release. [3]

## Prerequisites: do not grant permissions for a bonus

1. An **existing**, owner-approved SRE Agent and known tenant, subscription,
   agent resource group and name. Use `<TENANT_ID>`, `<SUBSCRIPTION_ID>`,
   `<AGENT_RESOURCE_GROUP>`, `<AGENT_NAME>` and `<THREAD_ID>` as portable
   placeholders; populate only in a private operator context.
2. A supported client already installed and approved for the data being shown:
   GitHub Copilot CLI, VS Code with Copilot, Claude Code, or Claude Desktop.
   Organization policy can prohibit servers or external model processing.
3. Node.js with npm/npx available to the **host actually launching the MCP
   process**. Microsoft supplies an NPM route; a .NET alternative is documented
   but is unnecessary for this bonus. [2][3]
4. Existing Azure CLI sign-in on that same host and existing appropriate access.
   Azure MCP Server uses Azure Identity; sign in **before** starting the server.
   Microsoft warns that interactive fallback is suppressed in server mode. [1][5]
5. Existing **Reader** access for control-plane discovery and, for thread reads,
   existing **SRE Agent Administrator** access on the agent, as documented in
   [1]. This is not a read-only data-plane RBAC role. Do not add it, broaden
   scope, approve new consent, or change the agent identity just for this demo.
   Missing access means skip the service read.
6. A short, completed, owner-reviewed thread concerning only your selected
   targets, safe for the client/model and intended audience. The thread GET can
   return its existing message history; asking for a five-bullet summary does
   **not** limit bytes returned by the service. Do not choose a broad incident
   thread, raw event dump, credential-bearing thread, or active investigation.

For separately approved attendee setup, the documented local sign-in method is:

```powershell
az login --tenant "<TENANT_ID>"
az account show
```

Do this in a private terminal. Do not export tokens or store them in
configuration, source, prompts, screenshots or receipts. No `az account
get-access-token` command or token-scope guessing is required. The published
server handles its ARM and SRE data-plane token acquisition separately. [1][5]

**Resource-version gate:** reviewed Azure MCP source discovers
`Microsoft.App/agents` and resolves `properties.agentEndpoint` with legacy
property fallbacks. Do not assume another preview resource type, such as
`Microsoft.SreAgent`, is interchangeable or rewrite an ID to make discovery
succeed. If your exact existing agent is not returned or cannot be resolved,
stop; this bonus does not authorize agent migration/recreation. [1][4]

## Small, read-only server configuration

Use a **new named entry** `sre-bonus-readonly`; preserve existing servers.
The reviewed server supports explicit `--tool` filtering (which selects
individual-tool mode) and `--read-only`. Do not combine `--tool` with
`--namespace`. Expose just:

- `sreagent_agents_list`: approved resource-group-filtered discovery.
- `sreagent_threads_get`: one already-reviewed thread's existing messages.

This is narrower than the official general quickstart's full catalogue.
`--read-only` filters commands by their server metadata; it does not reduce
RBAC permissions, constrain resource IDs, sanitize every message, or constrain
other servers and shell tools in the client. Disable unrelated tools for this
bonus where the client supports it and review every proposed invocation. [4]

### GitHub Copilot CLI

Preferred guided route: run `copilot`, then `/mcp add`. Choose **STDIO** (or
Local on older clients), name `sre-bonus-readonly`, and enter:

```text
npx -y @azure/mcp@3.0.0-beta.50 server start --read-only --tool sreagent_agents_list --tool sreagent_threads_get
```

Environment variables:

```json
{"AZURE_TOKEN_CREDENTIALS":"AzureCliCredential"}
```

Tools: `sreagent_agents_list,sreagent_threads_get`. Save with **Ctrl+S**.
The credential pin is a nonsecret setting, not a token. [2][5][6]

Equivalent entry in **`%USERPROFILE%\.copilot\mcp-config.json`**:

```json
{
  "mcpServers": {
    "sre-bonus-readonly": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y", "@azure/mcp@3.0.0-beta.50", "server", "start",
        "--read-only",
        "--tool", "sreagent_agents_list",
        "--tool", "sreagent_threads_get"
      ],
      "env": {"AZURE_TOKEN_CREDENTIALS": "AzureCliCredential"},
      "tools": ["sreagent_agents_list", "sreagent_threads_get"]
    }
  }
}
```

Merge the entry; do not replace an existing file. Current GitHub documentation
uses `mcp-config.json`, despite the SRE overview's `mcp.json` shorthand.
Copilot CLI does not read the VS Code `servers` wrapper. Inspect status/tools
with `/mcp show sre-bonus-readonly` on current clients; use `/mcp help` for
version-specific command differences. A saved entry is not connection proof.
Do not use `--allow-all-tools` or unattended approval modes. [2][6]

### VS Code with GitHub Copilot

Microsoft's one-click route is the **Azure MCP Server** extension,
publisher `ms-azuretools`, identifier
`ms-azuretools.vscode-azure-mcp-server`. It auto-updates preview versions and
may expose more tools than this demonstration requires. Do not install a
duplicate server alongside an existing extension instance without reviewing
which tools are enabled. [7]

For a separate pinned entry, use **MCP: Open User Configuration** in an approved
profile. VS Code also supports `.vscode\mcp.json` with this format:

```json
{
  "servers": {
    "sre-bonus-readonly": {
      "type": "stdio",
      "command": "npx",
      "args": [
        "-y", "@azure/mcp@3.0.0-beta.50", "server", "start",
        "--read-only",
        "--tool", "sreagent_agents_list",
        "--tool", "sreagent_threads_get"
      ],
      "env": {"AZURE_TOKEN_CREDENTIALS": "AzureCliCredential"}
    }
  }
}
```

Use Copilot's agent/tool-capable chat, review server trust, and **Configure
Tools** to enable only the two reads. Current VS Code also documents portable
`.mcp.json` using `mcpServers`; the `servers` wrapper above specifically belongs
to its VS Code-format `mcp.json`. Remote workspaces may launch the process on
a different host; local CLI login is not necessarily available there. [7][8]

### Claude Code

The official Microsoft README offers an Azure plugin; that bundles additional
skills/tools and is not necessary for this restricted bonus. Use Claude's
documented local stdio registration instead: [3][9]

```powershell
claude mcp add --scope user --env AZURE_TOKEN_CREDENTIALS=AzureCliCredential --transport stdio sre-bonus-readonly -- npx -y @azure/mcp@3.0.0-beta.50 server start --read-only --tool sreagent_agents_list --tool sreagent_threads_get
```

The `--` separates Claude options from server arguments. `--scope user` avoids
writing project-wide configuration. Claude's project `.mcp.json` uses a
`mcpServers` wrapper with `type`, `command`, `args` and `env`, not VS Code's
`servers` or Copilot-specific `tools` entry. Inspect with `claude mcp get
sre-bonus-readonly` or `/mcp`; do not use
`--dangerously-skip-permissions`. [9]

### Claude Desktop

Microsoft documents installing the platform-specific **MCPB** from the Azure
release into Desktop (drag into the app, or Extensions → Advanced Settings →
Install Extension). The October 6 release includes Windows x64/ARM64 and macOS
bundles. This verifies an installation route, **not** a narrow tool allowlist
or successful SRE login in Desktop. Prefer the manual pinned entry for this
bonus rather than assuming bundle defaults are read-only. [3]

Desktop's manual configuration is **Settings → Developer → Edit Config**,
on Windows `%APPDATA%\Claude\claude_desktop_config.json`. Use `mcpServers`;
copy the following entry into that wrapper:

```json
{
  "mcpServers": {
    "sre-bonus-readonly": {
      "command": "npx",
      "args": [
        "-y", "@azure/mcp@3.0.0-beta.50", "server", "start",
        "--read-only",
        "--tool", "sreagent_agents_list",
        "--tool", "sreagent_threads_get"
      ],
      "env": {"AZURE_TOKEN_CREDENTIALS": "AzureCliCredential"}
    }
  }
}
```

Completely quit and reopen Desktop, then inspect the connector/tool list.
These are local servers, **not** a claude.ai remote web connector. Desktop's
GUI environment must be able to launch npx and access the signed-in Azure CLI.
If launch/PATH fails, diagnose privately using client logs and official
troubleshooting; do not add secrets or disable security.
The manual wrapper/path is documented by the MCP project's Claude Desktop
guide; Microsoft separately lists Desktop as supported. [1][10]

## Try the scoped reads

First verify server startup, the exact two tools and the intended caller/agent.
Review each proposed invocation against your approved tenant, subscription and
resource group. Use one discovery call and one GET for the reviewed completed
thread, then summarize without more tools. Empty or denied results mean Unknown,
not permission to search other subscriptions, grant access or retry in a loop.

### Read-only sample prompts

**1 — discover only the intended scope**

```text
Use only sre-bonus-readonly / sreagent_agents_list, once.
Tenant <TENANT_ID>, subscription <SUBSCRIPTION_ID>, resource group
<AGENT_RESOURCE_GROUP>. Show only the entry matching <AGENT_NAME>,
its resource type, provisioning state and whether an endpoint was returned.
Do not display the endpoint, query other groups/subscriptions, create anything,
or start an investigation. If missing or denied, stop and report Unknown.
```

**2 — retrieve existing SRE context, not new work**

```text
Use only sre-bonus-readonly / sreagent_threads_get, once, for existing agent
<AGENT_NAME>, tenant <TENANT_ID>, subscription <SUBSCRIPTION_ID>,
resource group <AGENT_RESOURCE_GROUP>, thread <THREAD_ID>.
This thread was reviewed for <APPROVED_TARGETS> only. Retrieve its existing messages;
do not send a message, continue/run an investigation, call private guest tools,
query logs, change incident state, start services, or invoke remediation.
Summarize in five bullets: target, observed source timestamps, last evidenced
connectivity/service state if present, permission/provider gaps, and what remains Unknown.
Historical Connected/Running or task completion is not current-health proof.
```

**3 — reason locally from that response**

```text
Without calling any tool, turn the returned evidence for <APPROVED_TARGETS> into a short
operator handoff: observed facts with UTC timestamps, unknowns, and the next
verification requiring human approval. Do not infer application/database health
from machine names, infer physical-site root cause, or claim a repair occurred.
```

Do not substitute “investigate the environment.” The published server has
thread creation, send-message, investigation, connector/task/incident/workflow
management and knowledge-write operations in its wider catalogue. Those are
**excluded** here. `threads investigate` has multistep defaults; `investigate_yolo`
can bypass **all** approval gates, including infrastructure modifications.
Neither belongs in this bonus. Client approval, native SRE action approval,
caller RBAC and the SRE managed identity's downstream rights are separate
boundaries. Read-only wording in a prompt is not enforcement. [1][4]

## Troubleshooting and related guides

If the local server cannot start, inspect the client logs before claiming a
connection. If ARM discovery succeeds but thread reading
fails, label only control-plane discovery accepted; data-plane access is Unknown.
Never call endpoint discovery successful agent reasoning.

You can inspect the already-reviewed completed thread in the **SRE Agent web
experience**, but that does not validate the MCP connection. With no safe
existing thread, skip the service read.

- [Component selection](../README.md) and ordinary-server boundaries.
- [Setup](setup.md): prerequisites, permissions and costs.
- [Guest setup](guest-setup.md): the **opposite-direction** connector trust route.
- [Safety and cleanup](safety-and-reset.md).
- [First-party source register](sources.md).

Do not ingest this guide or the exercise repository into SRE knowledge.
No agent configuration changes are needed for these existing-thread reads;
operations and recovery verification remain separate.

## Sources

Links reviewed **October 10, 2026**. Check version compatibility before setup;
documentation and tagged source are not runtime acceptance.

1. [Microsoft Learn — SRE Agent MCP server](https://learn.microsoft.com/en-us/azure/sre-agent/mcp-server):
   direction, Azure MCP proxy, endpoint discovery, clients, ARM/data-plane roles,
   auth and unsafe autonomous-mode warning.
2. [Microsoft Learn — Copilot CLI quickstart](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/how-to/github-copilot-cli):
   local npx server, Azure CLI sign-in and guided registration.
3. [Microsoft Azure MCP release 3.0.0-beta.50](https://github.com/microsoft/mcp/releases/tag/Azure.Mcp.Server-3.0.0-beta.50)
   and [tagged server README](https://github.com/microsoft/mcp/blob/Azure.Mcp.Server-3.0.0-beta.50/servers/Azure.Mcp.Server/README.md):
   exact NPM version, MCPB assets, supported installation routes. Latest Azure
   release found in the reviewed release listing, not a promise about future releases.
4. Tagged Microsoft implementation:
   [server options](https://github.com/microsoft/mcp/blob/Azure.Mcp.Server-3.0.0-beta.50/core/Microsoft.Mcp.Core/src/Areas/Server/Options/ServerStartOptions.cs),
   [SRE tool registration](https://github.com/microsoft/mcp/blob/Azure.Mcp.Server-3.0.0-beta.50/tools/Azure.Mcp.Tools.SreAgent/src/SreAgentSetup.cs),
   [thread GET](https://github.com/microsoft/mcp/blob/Azure.Mcp.Server-3.0.0-beta.50/tools/Azure.Mcp.Tools.SreAgent/src/Commands/Threads/ThreadsGetCommand.cs),
   [thread options](https://github.com/microsoft/mcp/blob/Azure.Mcp.Server-3.0.0-beta.50/tools/Azure.Mcp.Tools.SreAgent/src/Options/Threads/ThreadsGetOptions.cs).
   Endpoint/API/auth implementation also reviewed at main commit
   [`406c2dbd3b7ef1e4341e449103732f0cb7b59c47`](https://github.com/microsoft/mcp/blob/406c2dbd3b7ef1e4341e449103732f0cb7b59c47/tools/Azure.Mcp.Tools.SreAgent/src/Services/SreAgentService.cs)
   (October 9). Source inspection, not executed client tests.
5. [Microsoft Azure MCP authentication](https://github.com/microsoft/mcp/blob/406c2dbd3b7ef1e4341e449103732f0cb7b59c47/docs/Authentication.md):
   `AZURE_TOKEN_CREDENTIALS=AzureCliCredential`; no manual token needed.
6. [GitHub — Add MCP servers to Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers):
   authoritative CLI schema/path, stdio support, trust and per-tool selection.
7. [Microsoft Learn — VS Code quickstart](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/get-started/tools/visual-studio-code):
   extension identity, manual `servers` configuration and authentication.
8. [VS Code — Add and manage MCP servers](https://code.visualstudio.com/docs/agent-customization/mcp-servers):
   user/workspace/portable formats, trust and tool selection.
9. [Anthropic — Claude Code MCP reference](https://code.claude.com/docs/en/mcp):
   local stdio command, scope, environment options, `--` separator and status checks.
10. [MCP project — Claude Desktop local-server guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers):
    Desktop `mcpServers` shape, Windows config path and restart requirement.
