targetScope = 'resourceGroup'

type target = {
  resourceId: string
  @minValue(1)
  totalMemoryMiB: int
  @minLength(1)
  disks: string[]
}

@description('Unique installation name. Scripts reject existing names without the matching ownership receipt.')
@minLength(1)
@maxLength(50)
param namePrefix string
param location string
param workspaceResourceId string
@minLength(1)
@maxLength(50)
param targets target[]
@description('Unique installation UUID, retained in the private ownership receipt.')
param ownerToken string
param enabled bool = true
@allowed([5, 10, 15])
param frequencyMinutes int = 5
@allowed([15, 30])
param sustainedMinutes int = 15
@minValue(5)
@maxValue(30)
param freshnessMinutes int = 10
@minValue(0)
@maxValue(10)
param ingestionLagMinutes int = 2
@minValue(1)
@maxValue(30)
param minSamplesPerBin int = 3
@allowed(['Available Bytes', 'Available MBytes'])
param memoryCounter string = 'Available Bytes'
@minValue(1)
@maxValue(100)
param cpuThresholdPercent int = 90
@minValue(1)
@maxValue(100)
param memoryAvailableThresholdPercent int = 10
@minValue(1)
@maxValue(100)
param diskFreeThresholdPercent int = 10
@allowed([5, 10, 15])
param recoveryMinutes int = 10
@description('Optional existing action groups. Native SRE incident intake is configured separately.')
param actionGroupIds string[] = []

var inventory = replace(replace(replace(replace(replace(loadTextContent('queries/inventory.kql'),
  '__TARGETS__', string(targets)), '__FRESHNESS__', string(freshnessMinutes)),
  '__LAG__', string(ingestionLagMinutes)), '__SUSTAINED__', string(sustainedMinutes)),
  '__MIN_SAMPLES__', string(minSamplesPerBin))
var definitions = [
  { suffix: 'heartbeat', body: loadTextContent('queries/heartbeat.kql'), threshold: 0, operator: 'GreaterThan', severity: 2 }
  { suffix: 'cpu', body: loadTextContent('queries/cpu.kql'), threshold: cpuThresholdPercent, operator: 'GreaterThan', severity: 2 }
  { suffix: 'memory', body: loadTextContent('queries/memory.kql'), threshold: memoryAvailableThresholdPercent, operator: 'LessThan', severity: 2 }
  { suffix: 'disk', body: loadTextContent('queries/disk.kql'), threshold: diskFreeThresholdPercent, operator: 'LessThan', severity: 2 }
  { suffix: 'coverage', body: loadTextContent('queries/coverage.kql'), threshold: 0, operator: 'GreaterThan', severity: 3 }
]

resource rules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for rule in definitions: {
  name: '${namePrefix}-${rule.suffix}'
  location: location
  kind: 'LogAlert'
  tags: {
    'hybrid-monitoring-owner': ownerToken
    'hybrid-monitoring-component': 'baseline-v1'
  }
  properties: {
    displayName: '${namePrefix}-${rule.suffix}'
    description: 'Explicit Windows inventory: ${rule.suffix}. Missing telemetry is not proof of power loss or Arc disconnection. Check coverage before claiming recovery.'
    enabled: enabled
    severity: rule.severity
    scopes: [workspaceResourceId]
    evaluationFrequency: 'PT${frequencyMinutes}M'
    windowSize: 'PT${sustainedMinutes}M'
    // Includes aligned closed bins, ingestion lag and freshness; never a historical all-time scan.
    overrideQueryTimeRange: 'PT1H'
    // The provider rejects autoMitigate alongside resolveConfiguration.
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT${recoveryMinutes}M'
    }
    skipQueryValidation: false
    criteria: {
      allOf: [{
        query: '${trim(inventory)}\n${trim(replace(rule.body, '__MEMORY_COUNTER__', memoryCounter))}'
        timeAggregation: 'Maximum'
        metricMeasureColumn: 'Value'
        resourceIdColumn: '_ResourceId'
        operator: rule.operator
        threshold: rule.threshold
        dimensions: [
          { name: '_ResourceId', operator: 'Include', values: ['*'] }
          { name: 'InstanceName', operator: 'Include', values: ['*'] }
          { name: 'Signal', operator: 'Include', values: ['*'] }
        ]
        failingPeriods: {
          numberOfEvaluationPeriods: 1
          minFailingPeriodsToAlert: 1
        }
      }]
    }
    actions: {
      actionGroups: actionGroupIds
    }
  }
}]

output ruleIds string[] = [for (definition, i) in definitions: rules[i].id]
