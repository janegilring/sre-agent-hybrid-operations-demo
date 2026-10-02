targetScope = 'resourceGroup'

@description('Fresh UUID identifying this separately owned alert. Never reuse an existing alert ownership ID.')
@minLength(36)
@maxLength(36)
param ownershipId string

@description('Exact existing Microsoft.HybridCompute/machines IDs in the deployment subscription. Validate inputs and GET every resource before deployment.')
@minLength(1)
param machineResourceIds string[]

@description('Optional existing action group IDs. Empty means no action-group notifications; no destinations are created.')
param actionGroupResourceIds string[] = []

resource connectivityAlerts 'Microsoft.Insights/activityLogAlerts@2020-10-01' = [for machineId in machineResourceIds: {
  name: 'arc-connectivity-single-${guid(toLower(ownershipId), toLower(machineId))}'
  location: 'global'
  tags: {
    'arc-connectivity-owner': ownershipId
    'managed-by': 'hybrid-arc-connectivity'
  }
  properties: {
    enabled: true
    description: 'Arc Resource Health Available to Unavailable transition; not current inventory, AMA heartbeat, outage cause, or recovery proof.'
    scopes: [
      machineId
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'resourceType'
          equals: 'Microsoft.HybridCompute/machines'
        }
        {
          field: 'properties.previousHealthStatus'
          equals: 'Available'
        }
        {
          field: 'properties.currentHealthStatus'
          equals: 'Unavailable'
        }
        // A single flat equality excludes scope-prefix siblings and descendants.
        {
          field: 'resourceId'
          equals: machineId
        }
      ]
    }
    actions: {
      actionGroups: [for actionGroupId in actionGroupResourceIds: {
        actionGroupId: actionGroupId
      }]
    }
  }
}]

output alertResourceIds array = [for (machineId, index) in machineResourceIds: connectivityAlerts[index].id]
output ownershipTag string = ownershipId
