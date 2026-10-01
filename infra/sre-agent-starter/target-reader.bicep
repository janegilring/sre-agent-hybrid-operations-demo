param principalId string
param ownershipToken string

resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, 'Reader', ownershipToken)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: principalId
    principalType: 'ServicePrincipal'
    description: 'sre-agent-starter:${ownershipToken}'
  }
}
output roleAssignmentId string = reader.id
