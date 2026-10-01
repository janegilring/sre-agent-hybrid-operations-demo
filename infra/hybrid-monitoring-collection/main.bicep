targetScope = 'resourceGroup'

@description('Unique new collection name. Never reuse an existing DCR or association name.')
param name string
@description('Existing workspace region.')
param location string
param workspaceResourceId string
@minLength(2)
@maxLength(2)
@description('Exactly two existing Windows Arc machines in this resource group.')
param machineNames string[]
@description('Unique ownership token recorded before deployment.')
param ownerToken string

resource machines 'Microsoft.HybridCompute/machines@2024-07-10' existing = [for machineName in machineNames: {
  name: machineName
}]

resource diskCollection 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: name
  location: location
  kind: 'Windows'
  tags: {
    component: 'hybrid-monitoring-collection'
    ownerToken: ownerToken
  }
  properties: {
    description: 'Additive Windows disk free-space collection; existing monitoring is preserved.'
    dataSources: {
      performanceCounters: [
        {
          name: 'logicalDiskFreeSpace'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: ['\\LogicalDisk(*)\\% Free Space']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'existingWorkspace'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: ['existingWorkspace']
      }
    ]
  }
}

resource associations 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [for (machineName, i) in machineNames: {
  name: name
  scope: machines[i]
  properties: {
    description: 'hybrid-monitoring-collection ownerToken=${ownerToken}'
    dataCollectionRuleId: diskCollection.id
  }
}]

output collectionId string = diskCollection.id
output associationIds array = [for (machineName, i) in machineNames: associations[i].id]
