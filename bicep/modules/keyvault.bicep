// ============================================================
// Module: Azure Key Vault
// Creates Key Vault for storing secrets (passwords, SSH keys, certificates)
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('Key Vault name (must be globally unique, 3-24 chars)')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Azure AD Tenant ID')
param tenantId string

@description('Object ID of the user/service principal to grant initial access')
param adminObjectId string

@description('Enable soft delete (recommended for production)')
param enableSoftDelete bool = true

@description('Soft delete retention period in days')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Enable purge protection (prevents permanent deletion)')
param enablePurgeProtection bool = true

@description('Tags to apply to resources')
param tags object = {}

// ----- Key Vault -----

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
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null
    enableRbacAuthorization: false // Using access policies
    enabledForDeployment: true // Allow VMs to retrieve secrets during deployment
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true // Allow ARM/Bicep to retrieve secrets
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow' // Can be restricted to 'Deny' with specific VNet rules
    }
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: adminObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'create'
            'update'
            'delete'
            'backup'
            'restore'
            'recover'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'backup'
            'restore'
            'recover'
          ]
          certificates: [
            'get'
            'list'
            'create'
            'update'
            'delete'
            'managecontacts'
            'manageissuers'
            'getissuers'
            'listissuers'
            'setissuers'
            'deleteissuers'
          ]
        }
      }
    ]
  }
}

// ----- Outputs -----

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
