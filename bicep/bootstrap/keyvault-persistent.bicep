// ============================================================
// Bootstrap: Persistent Key Vault — SC MEDIA SRL
// Deployed to rg-mediasrl-persistent (survives main RG teardowns).
// Run ONCE before any main.bicep deployment via:
//   scripts/0-bootstrap-keyvault.ps1
//
// Referenced by prod.bicepparam / dev.bicepparam via az.getSecret().
// enabledForTemplateDeployment: true is required for az.getSecret().
// ============================================================

targetScope = 'resourceGroup'

@description('Azure region')
param location string = 'swedencentral'

@description('Key Vault name (globally unique, 3-24 chars)')
param keyVaultName string = 'kv-mediasrl-persistent'

@description('Azure AD Tenant ID')
param tenantId string

@description('Object ID of admin user or service principal (gets secret get/set/list)')
param adminObjectId string

@description('Tags')
param tags object = {
  environment: 'persistent'
  project: 'mediasrl'
  owner: 'IT Security SRL'
  'managed-by': 'bicep'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: false
    enabledForTemplateDeployment: true  
    enabledForDeployment: false
    enabledForDiskEncryption: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: adminObjectId
        permissions: {
          secrets: ['get', 'list', 'set', 'delete', 'backup', 'restore', 'recover']
        }
      }
    ]
  }
}

output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
