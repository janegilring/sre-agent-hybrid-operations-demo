targetScope = 'resourceGroup'

@description('Fresh installation UUID; reuse only with unchanged, verified ownership receipts.')
@minLength(36)
@maxLength(36)
param installationId string
@description('Existing Windows Arc guest in this deployment resource group. Never a cluster host.')
param machineName string
@description('Existing Log Analytics workspace ARM ID; DCR location must match its region.')
param workspaceResourceId string
param location string
@description('False creates collection only. True creates the event alert after Event schema/locale verification.')
param deployAlert bool = false
@description('Optional existing action groups. Does not configure SRE incident routing.')
param actionGroupIds string[] = []

var prefix = 'spooler-${installationId}'
var owner = 'hybrid-service-monitoring:${installationId}'
var query = replace(loadTextContent('stopped-transition.kql'), '__TARGET_RESOURCE_IDS__', string([machine.id]))

resource machine 'Microsoft.HybridCompute/machines@2024-07-10' existing = {
  name: machineName
}

resource collection 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${prefix}-events'
  location: location
  kind: 'Windows'
  tags: { 'hybrid-service-monitoring-owner': installationId }
  properties: {
    description: '${owner}; English Print Spooler transitions only; not state inventory.'
    dataSources: {
      windowsEventLogs: [{
        name: 'spoolerTransitions'
        streams: ['Microsoft-Event']
        xPathQueries: [
          'System!*[System[Provider[@Name=\'Service Control Manager\'] and (EventID=7036)] and EventData[Data[@Name=\'param1\']=\'Print Spooler\']]'
        ]
      }]
    }
    destinations: {
      logAnalytics: [{ name: 'workspace', workspaceResourceId: workspaceResourceId }]
    }
    dataFlows: [{
      streams: ['Microsoft-Event']
      destinations: ['workspace']
      transformKql: 'source'
      outputStream: 'Microsoft-Event'
    }]
  }
}

resource association 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${prefix}-association'
  scope: machine
  properties: {
    description: owner
    dataCollectionRuleId: collection.id
  }
}

resource stoppedAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = if (deployAlert) {
  name: '${prefix}-stopped-transition'
  location: location
  kind: 'LogAlert'
  tags: { 'hybrid-service-monitoring-owner': installationId }
  properties: {
    displayName: 'Spooler stopped transition observed — verify current state'
    description: '${owner}; Event age <=10m, ingestion age <=5m. No result/expiry is NOT Running. Read fixed Spooler state before proposing a repair.'
    enabled: true
    severity: 2
    scopes: [workspaceResourceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    overrideQueryTimeRange: 'PT10M'
    // Stateless event evidence: neither auto-resolution nor event aging proves service recovery.
    autoMitigate: false
    skipQueryValidation: false
    criteria: {
      allOf: [{
        query: query
        timeAggregation: 'Count'
        resourceIdColumn: '_ResourceId'
        operator: 'GreaterThan'
        threshold: 0
        failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
      }]
    }
    actions: { actionGroups: actionGroupIds }
  }
}

output collectionId string = collection.id
output associationId string = association.id
output alertId string = deployAlert ? stoppedAlert!.id : ''
output canonicalQuery string = query
