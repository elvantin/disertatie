// ============================================================
// Main Orchestrator — SC MEDIA SRL Infrastructure
// Deploys complete Azure infrastructure using modular Bicep
// ============================================================

targetScope = 'subscription'

// ----- Parameters -----

@description('Azure region for all resources')
param location string = 'swedencentral'

@description('Environment (productie/dezvoltare)')
@allowed([
  'productie'
  'dezvoltare'
])
param environment string = 'productie'

@description('Resource Group name')
param resourceGroupName string = 'rg-mediasrl-${environment}-${location}'

@description('VNet name')
param vnetName string = 'vnet-mediasrl-${environment}'

@description('VNet address space')
param vnetAddressSpace string = '10.10.0.0/20'

@description('Production subnet address prefix')
param subnetProdPrefix string = '10.10.10.0/24'

@description('Development subnet address prefix')
param subnetDevPrefix string = '10.10.11.0/24'

@description('Management subnet address prefix')
param subnetMgmtPrefix string = '10.10.12.0/24'

@description('Admin IP address for RDP access (CIDR, e.g., "1.2.3.4/32")')
param adminIpAddress string

@description('Key Vault name')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-mediasrl-${environment}'

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string = 'log-mediasrl-${environment}'

@description('Azure AD Tenant ID')
param tenantId string

@description('Admin Object ID for Key Vault access')
param adminObjectId string

@description('Azure Compute Gallery name')
param computeGalleryName string = 'gal_mediasrl'

@description('Ubuntu 22.04 LTS image definition name in gallery')
param ubuntuImageDefinition string = 'imgdef-ubuntu2204'

@description('Windows Server 2022 image definition name in gallery')
param windowsImageDefinition string = 'imgdef-winserver2022'

@description('Image version to use from gallery')
param imageVersion string = '1.0.0'

@description('Admin username for VMs')
param adminUsername string = 'azureadmin'

@description('Admin password for Windows VMs')
@secure()
param adminPassword string

@description('SSH public key for Linux VMs')
param sshPublicKey string

@description('Use Marketplace images instead of Gallery (set to false once Packer images are built)')
param useMarketplaceImages bool = true

@description('Recovery Services Vault name for Azure Backup')
param backupVaultName string = 'rsv-mediasrl-${environment}'

@description('Persistent Resource Group name (survives az group delete on main RG)')
param persistentResourceGroupName string = 'rg-mediasrl-persistent'

@description('Persistent Public IPs (created in persistent RG, reused across deployments)')
param persistentPublicIps array = [
  {
    name: 'pip-vm-jmp-01'
    vmName: 'vm-jmp-01'
    dnsLabel: ''
  }
  {
    name: 'pip-vm-web-01'
    vmName: 'vm-web-01'
    dnsLabel: 'mediasrl'
  }
]

@description('VM configurations')
param vms array = [
  // === ACTIVE VMs for Testing ===
  {
    name: 'vm-jmp-01'
    osType: 'Linux'
    size: 'Standard_D2s_v3'
    subnet: 'mgmt'
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 64
  }
  {
    name: 'vm-web-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
  {
    name: 'vm-db-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'windows'
    osDiskSizeGb: 128
  }
  // === DISABLED VMs (uncomment when ready for full deployment) ===
  {
    name: 'vm-fs-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'windows'
    osDiskSizeGb: 128
  }
  {
    name: 'vm-app-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
  {
    name: 'vm-cms-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
]

// ----- Variables -----

var tags = {
  environment: environment
  project: 'mediasrl'
  owner: 'IT Security SRL'
  'managed-by': 'bicep'
}

// ----- Bootstrap Scripts (loaded at compile time, passed to Custom Script Extension) -----

var jumphostBootstrapScript = loadTextContent('../scripts/bootstrap-jumphost.sh')
var windowsWinrmBootstrapScript = loadTextContent('../scripts/bootstrap-windows-winrm.ps1')

var galleryResourceGroupName = resourceGroupName
var galleryImageIdUbuntu = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${galleryResourceGroupName}/providers/Microsoft.Compute/galleries/${computeGalleryName}/images/${ubuntuImageDefinition}/versions/${imageVersion}'
var galleryImageIdWindows = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${galleryResourceGroupName}/providers/Microsoft.Compute/galleries/${computeGalleryName}/images/${windowsImageDefinition}/versions/${imageVersion}'

// ----- Module: Resource Group -----

module resourceGroup 'modules/resource-group.bicep' = {
  name: 'deploy-rg'
  params: {
    resourceGroupName: resourceGroupName
    location: location
    environment: environment
    project: 'mediasrl'
    owner: 'IT Security SRL'
  }
}

// ----- Module: Persistent Resource Group (survives environment teardowns) -----

module persistentRg 'modules/resource-group.bicep' = {
  name: 'deploy-persistent-rg'
  params: {
    resourceGroupName: persistentResourceGroupName
    location: location
    environment: environment
    project: 'mediasrl'
    owner: 'IT Security SRL'
  }
}

// ----- Module: Persistent Public IPs (static IPs reused across deployments) -----

module persistentIps 'modules/persistent-ips.bicep' = {
  name: 'deploy-persistent-ips'
  scope: az.resourceGroup(persistentResourceGroupName)
  params: {
    location: location
    tags: tags
    publicIps: persistentPublicIps
  }
  dependsOn: [
    persistentRg
  ]
}

// ----- Module: Azure Policy (Subscription Scope) -----

module policy 'modules/policy.bicep' = {
  name: 'deploy-policy'
  params: {
    allowedLocations: [
      'swedencentral'
      'westeurope'
      'northeurope'
    ]
    requiredTags: [
      'environment'
      'project'
      'managed-by'
    ]
  }
}

// ----- Module: Network Security Groups -----

module nsg 'modules/nsg.bicep' = {
  name: 'deploy-nsg'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    environment: environment
    adminIpAddress: adminIpAddress
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// ----- Module: Networking (VNet, Subnets, Route Tables) -----

module networking 'modules/networking.bicep' = {
  name: 'deploy-networking'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    vnetName: vnetName
    vnetAddressSpace: vnetAddressSpace
    subnetProdName: 'snet-prod'
    subnetProdPrefix: subnetProdPrefix
    subnetDevName: 'snet-dev'
    subnetDevPrefix: subnetDevPrefix
    subnetMgmtName: 'snet-mgmt'
    subnetMgmtPrefix: subnetMgmtPrefix
    nsgProdId: nsg.outputs.nsgProdId
    nsgDevId: nsg.outputs.nsgDevId
    nsgMgmtId: nsg.outputs.nsgMgmtId
    tags: tags
  }
}

// ----- Module: Key Vault -----

module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    keyVaultName: keyVaultName
    tenantId: tenantId
    adminObjectId: adminObjectId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// ----- Module: Log Analytics Workspace -----

module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
    sku: 'PerGB2018'
    retentionInDays: 31
    dailyQuotaGb: 0 // Leverage 5 GB free tier
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// ----- Module: Azure Backup (Recovery Services Vault) -----
// DISABLED: Uncomment when ready to enable backup
// Recovery Services Vault is time-consuming to delete, so disabled for development

/*
module backup 'modules/backup.bicep' = {
  name: 'deploy-backup'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    vaultName: backupVaultName
    backupPolicyName: 'DailyBackupPolicy-1AM-14Days'
    backupTime: '01:00'
    retentionDays: 14
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}
*/

// ----- Module: Virtual Machines (Loop) -----

// Build a lookup: vmName → persistent public IP ID
// Used to attach pre-existing static IPs from the persistent resource group
var persistentIpLookup = reduce(persistentIps.outputs.publicIpIds, {}, (acc, ip) => union(acc, { '${ip.vmName}': ip.id }))

module virtualMachines 'modules/compute.bicep' = [for vm in vms: {
  name: 'deploy-${vm.name}'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    vmName: vm.name
    vmSize: vm.size
    osType: vm.osType
    adminUsername: adminUsername
    adminPasswordOrKey: adminPassword
    subnetId: vm.subnet == 'prod' ? networking.outputs.subnetProdId : (vm.subnet == 'dev' ? networking.outputs.subnetDevId : networking.outputs.subnetMgmtId)
    createPublicIp: vm.createPublicIp
    #disable-next-line prefer-safe-access
    existingPublicIpId: contains(persistentIpLookup, vm.name) ? persistentIpLookup[vm.name] : ''
    dnsLabel: vm.?dnsLabel ?? ''
    useGalleryImage: !useMarketplaceImages
    galleryImageId: vm.imageDefinition == 'ubuntu' ? galleryImageIdUbuntu : galleryImageIdWindows
    marketplacePublisher: useMarketplaceImages ? (vm.imageDefinition == 'ubuntu' ? 'canonical' : 'MicrosoftWindowsServer') : ''
    marketplaceOffer: useMarketplaceImages ? (vm.imageDefinition == 'ubuntu' ? 'ubuntu-22_04-lts' : 'WindowsServer') : ''
    marketplaceSku: useMarketplaceImages ? (vm.imageDefinition == 'ubuntu' ? 'server' : '2022-datacenter-azure-edition-smalldisk') : ''
    marketplaceVersion: 'latest'
    osDiskSizeGb: vm.osDiskSizeGb
    osDiskStorageType: 'StandardSSD_LRS'
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    deployMonitoringAgent: false // Disable to avoid package manager lock issues during deployment
    customScriptContent: vm.name == 'vm-jmp-01' ? jumphostBootstrapScript : (vm.osType == 'Windows' ? windowsWinrmBootstrapScript : '')
    tags: tags
  }
}]

// ----- Module: VM Backup Protection (Loop) -----
// DISABLED: Uncomment when ready to enable backup

/*
module vmBackupProtection 'modules/backup-vm.bicep' = [for (vm, i) in vms: {
  name: 'deploy-backup-${vm.name}'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    vaultName: backupVaultName
    vmName: vm.name
    vmId: virtualMachines[i].outputs.vmId
    backupPolicyId: backup.outputs.backupPolicyId
  }
  dependsOn: [
    virtualMachines
  ]
}]
*/

// NOTE: Bootstrap scripts run automatically at VM creation via Custom Script Extension
// - vm-jmp-01 (Linux): scripts/bootstrap-jumphost.sh (xRDP, Ansible, Azure CLI, etc.)
// - vm-db-01, vm-fs-01 (Windows): scripts/bootstrap-windows-winrm.ps1 (WinRM for Ansible)
// - Other Linux VMs: no bootstrap (configured by Ansible from jumphost)

// ----- Outputs -----

output resourceGroupName string = resourceGroup.outputs.resourceGroupName
output vnetId string = networking.outputs.vnetId
output vnetName string = networking.outputs.vnetName
output keyVaultName string = keyVault.outputs.keyVaultName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
output logAnalyticsWorkspaceName string = monitoring.outputs.workspaceName

output vmOutputs array = [for (vm, i) in vms: {
  name: virtualMachines[i].outputs.vmName
  privateIp: virtualMachines[i].outputs.privateIpAddress
  publicIp: virtualMachines[i].outputs.publicIpAddress
}]
