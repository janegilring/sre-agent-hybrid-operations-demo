# Public first-party sources

Retrieved/reviewed 2026-10-01 UTC. Learn source version is the live page on this
date unless a documentation view is specified; those views are not immutable
revisions or installed-release evidence. These links ground original prose,
not copied implementation, live observations or blanket execution authority.

| Source | Scope |
| --- | --- |
| [Azure Local health alerts](https://learn.microsoft.com/en-us/azure/azure-local/manage/health-alerts-via-azure-monitor-alerts?view=azloc-2609) | Built-in AzureEdgeAlerts; no custom rule/Log Analytics prerequisite for these faults |
| [Health Service faults](https://learn.microsoft.com/en-us/azure/azure-local/manage/health-service-faults?view=azloc-2609) | Raw severity, lifecycle, fault identity and catalog |
| [Support tools](https://learn.microsoft.com/en-us/azure/azure-local/manage/support-tools?view=azloc-2609) | Operator/admin collection, import-time update caveat; no execution provided |
| [Azure Local VM management](https://learn.microsoft.com/en-us/azure/azure-local/manage/azure-arc-vm-management-overview?view=azloc-2609) | Lifecycle/Resource Bridge and operation-specific support |
| [Azure Local VM FAQ](https://learn.microsoft.com/en-us/azure/azure-local/manage/azure-arc-vms-faq?view=azloc-2609) | Unmanaged VMs independently Arc-enabled as servers |
| [Arc Run Command](https://learn.microsoft.com/en-us/azure/azure-arc/servers/run-command) | Preview guest execution; distinct permissions and result states |
| [Arc security overview](https://learn.microsoft.com/en-us/azure/azure-arc/servers/security-overview) | Service-specific identities and local controls |
| [MCP connectors](https://learn.microsoft.com/en-us/azure/sre-agent/mcp-connectors) | Tool selection, transport/authentication and dynamic exposure |
| [SRE Azure Monitor integration](https://learn.microsoft.com/en-us/azure/sre-agent/azure-monitor-alerts) | Native incident scanner and permissions; not proof of actual routing |
| [Incident response plans](https://learn.microsoft.com/en-us/azure/sre-agent/incident-response-plans) | Review mode, matching and overlap |
| [Code Access](https://learn.microsoft.com/en-us/azure/sre-agent/connect-code-service) and [knowledge indexing](https://learn.microsoft.com/en-us/azure/sre-agent/connect-source-code) | Inspect effective authorization; repository selection is not a security boundary |

Official [Health Service faults workbook, pinned commit](https://github.com/Azure-Samples/AzureLocal/blob/c47b91ef5fc732f4c09821b69ff6057ae0a2e35f/health-service-faults/health-service-faults.xlsx):
commit `c47b91ef5fc732f4c09821b69ff6057ae0a2e35f`, blob
`32671b91f0b1d27314bf2a44e5f1433bccc61fdb`; public API identity verified
2026-10-01. Link only, no redistribution. Its metric catalog is not proof of
export/ingestion, and its severity representation must not be silently equated
with the Learn fault-property values or Azure Monitor Sev0-Sev4.

## Unresolved title attribution

The exact requested source title **"Power Azure SRE Agent with MCP tools"** was
not recovered by the 2026-10-01 search. It is not cited as an identified source.
The related official blog
[Power Azure SRE Agent with the tools it needs](https://devblogs.microsoft.com/azure-sdk/power-azure-sre-agent-with-connector-namespace/)
was retrieved, but concerns Connector Namespace and is **not claimed to be the
requested article**. This kit does not deploy Connector Namespace or copy that
blog's examples. Retain this open attribution item before public release.
