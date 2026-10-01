using './main.bicep'

// Replace all examples. Generate a NEW installationId with [guid]::NewGuid().
param installationId = '11111111-1111-4111-8111-111111111111'
param machineName = 'demo-windows-01'
param workspaceResourceId = '/subscriptions/00000000-0000-4000-8000-000000000000/resourceGroups/rg-demo-monitor/providers/Microsoft.OperationalInsights/workspaces/law-demo'
param location = 'westeurope'
param deployAlert = false
param actionGroupIds = []
