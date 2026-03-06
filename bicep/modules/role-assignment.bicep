// ============================================================
// Module: Role Assignment (generic)
// Assigns a built-in or custom role to a principal at the
// scope where this module is deployed.
// ============================================================

@description('Principal ID (Object ID) of the identity to assign the role to')
param principalId string

@description('Built-in role definition GUID (e.g. Reader: acdd72a7-3385-48ef-bd42-f606fba81ae7)')
param roleDefinitionId string

@description('Principal type (ServicePrincipal, User, Group)')
@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@description('Optional description for the role assignment')
param roleDescription string = ''

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
    description: roleDescription
  }
}
