using './main.bicep'

param agentName = 'sre-attendee-example'
param location = 'eastus2'
param targetResourceGroupNames = ['rg-attendee-workload']
param ownershipToken = '00000000-0000-0000-0000-000000000000'
param grantTargetReader = false
param agentAccessUserObjectIds = []
