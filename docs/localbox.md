# Optional whole-lab route: Azure Arc Jumpstart LocalBox

An ordinary Windows/JEA demo does not need LocalBox. For a nested Azure Local
learning environment, start with the official upstream rather than treating
this repository as a replacement deployment.

- [Official LocalBox guide](https://jumpstart.azure.com/azure_jumpstart_localbox)
- [Pinned official source](https://github.com/microsoft/azure_arc/tree/e2c114eed98d18105dcf3a718bef965d5112781b/azure_jumpstart_localbox)
- [Pinned Bicep entrypoint](https://github.com/microsoft/azure_arc/blob/e2c114eed98d18105dcf3a718bef965d5112781b/azure_jumpstart_localbox/bicep/main.bicep)

Verified on 2026-10-01 using the official site and GitHub API: commit
`e2c114eed98d18105dcf3a718bef965d5112781b` was current `main` and the latest
LocalBox-path commit, dated 2026-09-22. No release tags were returned. This is a
**reproducible default-branch pin, not an assertion of a certified stable
release**; upstream status was pending, not a passing certification.

## Sequence

1. Follow the official guide at the pinned source revision. Review Azure
   subscription/region eligibility, nested-virtualization SKU availability,
   quotas, credentials, licensing, network reachability and costs. Do not assume
   that deploying upstream is free or that stopped compute removes disk costs.
2. Validate the resulting lab according to upstream instructions. Inventory
   actual member servers, Azure resources and workload ownership. Do not
   redeploy an existing lab just to try this starter.
3. Deploy a **new** agent using the [SRE starter](../infra/sre-agent-starter/README.md).
   Keep scope explicit; approve connector permissions, network routing, OAuth
   and native configuration separately.
4. For Windows telemetry, first provide supported AMA collection and the exact
   workspace/counters/target IDs. Then use the [five-rule baseline](../infra/hybrid-monitoring/README.md).
   The optional [disk-only DCR](../infra/hybrid-monitoring-collection/README.md)
   covers exactly two existing Arc servers, not all collection onboarding.
5. On a selected domain member server, separately install and accept the
   [JEA capability](../tools/hybrid-server/README.md). Do not install it on
   a domain controller or grant administrative rights to obtain green results.
6. Build and configure the [portable private MCP host](../tools/private-mcp/README.md), then
   independently verify the authenticated network boundary, real provider reads,
   denied commands, and fresh native agent tool correlation.
7. Configure supported native response plans and notification accounts manually.
   Verify alert → incident → notification → fresh recovery → closure separately.
   No faults or automated remediation are authorized by these instructions.
8. Clean up only owned component resources using their receipts. For LocalBox
   itself use the pinned upstream lifecycle instructions and approved ownership
   inventory; never infer permission to delete a shared resource group.

No one-command whole-lab deployment or end-to-end acceptance was performed.
Upstream is linked, not copied; its CC BY 4.0 license and other upstream terms
remain applicable.
