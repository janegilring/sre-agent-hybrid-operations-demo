using './main.bicep'

// Illustrative only: generate a fresh UUID and replace every example ID before live preflight.
param ownershipId = '11111111-1111-4111-8111-111111111111'
param machineResourceIds = [
  '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-arc/providers/Microsoft.HybridCompute/machines/example-server'
]
param actionGroupResourceIds = []
