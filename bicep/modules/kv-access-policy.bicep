// Module: Key Vault Access Policy (add)
// Adds a single objectId to an existing vault's access policies without
// overwriting existing entries (operation: 'add').
// Must be deployed as a module from subscription-scoped Bicep files
// because child resources cannot cross scope boundaries inline.

param keyVaultName string

@description('AAD tenant ID')
param tenantId string

@description('Object ID of the principal to grant access (e.g. VM MSI principalId)')
param objectId string

@description('Secret permissions to grant')
param secretPermissions array = ['get', 'list']

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource accessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: kv
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: objectId
        permissions: {
          secrets: secretPermissions
        }
      }
    ]
  }
}
