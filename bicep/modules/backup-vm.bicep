// ============================================================
// Module: VM Backup Protection
// Configures backup protection for a single VM
// ============================================================

@description('Recovery Services Vault name')
param vaultName string

@description('VM name to protect')
param vmName string

@description('VM resource ID')
param vmId string

@description('Backup policy ID')
param backupPolicyId string

@description('Azure region for resources')
param location string

// ----- Backup Protection Container -----
// Note: Protection container and protected item are created implicitly
// when a backup is configured for a VM. This resource configures the link.

resource backupProtectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = {
  name: '${vaultName}/Azure/iaasvmcontainer;iaasvmcontainerv2;${split(vmId, '/')[4]};${vmName}/vm;iaasvmcontainerv2;${split(vmId, '/')[4]};${vmName}'
  location: location
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: backupPolicyId
    sourceResourceId: vmId
  }
}

// ----- Outputs -----

output protectedItemName string = backupProtectedItem.name
