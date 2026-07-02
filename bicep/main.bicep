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

// DISABLED: backup modules commented out — param unused until re-enabled
// @description('Recovery Services Vault name for Azure Backup')
// param backupVaultName string = 'rsv-mediasrl-${environment}'

@description('Azure AD Tenant ID')
param tenantId string

@description('Admin Object ID for Key Vault access')
param adminObjectId string

@description('Azure Compute Gallery name')
param computeGalleryName string = 'gal_mediasrl'

@description('Ubuntu 22.04 LTS base image definition name in gallery')
param ubuntuImageDefinition string = 'imgdef-ubuntu2204'

@description('Ubuntu 22.04 LTS jumphost image definition name in gallery')
param jumphostImageDefinition string = 'imgdef-ubuntu2204-jumphost'

@description('Windows Server 2022 image definition name in gallery')
param windowsImageDefinition string = 'imgdef-winserver2022'

@description('Image version to use from gallery. Use "latest" to automatically pick the newest Packer build.')
param imageVersion string = 'latest'

@description('Admin username for VMs')
param adminUsername string = 'azureadmin'

@description('Admin password for Windows VMs')
@secure()
param adminPassword string

@description('Use Marketplace images instead of Gallery (set to false once Packer images are built)')
param useMarketplaceImages bool = true

@description('Deploy Azure Monitor Agent on all VMs (requires Managed Identity on every VM)')
param deployAMA bool = true

@description('Alert email address for Azure Monitor notifications')
param alertEmail string = 'valentin.tita@qubitform.ro'

@description('Daily auto-shutdown time for all VMs in HHMM format (e.g. "2359"). Empty = disabled.')
param autoShutdownTime string = '2359'

@description('Timezone for auto-shutdown (Windows timezone ID)')
param autoShutdownTimezone string = 'E. Europe Standard Time'

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
    size: 'Standard_B4ls_v2'
    subnet: 'mgmt'
    createPublicIp: false
    imageDefinition: 'jumphost'
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
    dataDisks: [
      { lun: 0, diskSizeGB: 32, storageType: 'StandardSSD_LRS' }
    ]
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

var jumphostBootstrapScript = loadTextContent('../scripts/obsolete/bootstrap-jumphost.sh')
// Replace placeholder with actual password at compile time.
// Password comes from az.getSecret() in .bicepparam — never in plaintext in any file.
// The substituted script goes into CSE protectedSettings (encrypted by Azure).
var jumphostFinalizeScriptRaw = loadTextContent('../scripts/finalize-jumphost.sh')
var jumphostFinalizeScript = replace(jumphostFinalizeScriptRaw, '__ADMIN_PASSWORD_PLACEHOLDER__', adminPassword)
var windowsWinrmBootstrapScript = loadTextContent('scripts/windows-winrm-bootstrap.ps1')

var galleryResourceGroupName = 'rg-mediasrl-packer-${location}'
var galleryImageBase = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${galleryResourceGroupName}/providers/Microsoft.Compute/galleries/${computeGalleryName}/images'

// When imageVersion == 'latest', reference just the image definition — Azure auto-selects the newest published version.
// When a specific version is given (e.g. '1.0.2'), the exact version is pinned.
var galleryImageIdUbuntu   = imageVersion == 'latest' ? '${galleryImageBase}/${ubuntuImageDefinition}'   : '${galleryImageBase}/${ubuntuImageDefinition}/versions/${imageVersion}'
var galleryImageIdJumphost = imageVersion == 'latest' ? '${galleryImageBase}/${jumphostImageDefinition}' : '${galleryImageBase}/${jumphostImageDefinition}/versions/${imageVersion}'
var galleryImageIdWindows  = imageVersion == 'latest' ? '${galleryImageBase}/${windowsImageDefinition}'  : '${galleryImageBase}/${windowsImageDefinition}/versions/${imageVersion}'

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
  }
}

// ----- Module: Network Security Groups -----

module nsg 'modules/nsg.bicep' = {
  name: 'deploy-nsg'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
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

// ----- Module: Azure Backup (Recovery Services Vault + Daily Policy 1AM, 14-day retention) -----
// DISABLED: RSV vault cannot be force-deleted and blocks resource group teardown.
// Re-enable when a clean teardown procedure is confirmed.

// module backup 'modules/backup.bicep' = {
//   name: 'deploy-backup'
//   scope: az.resourceGroup(resourceGroupName)
//   params: {
//     location: location
//     vaultName: backupVaultName
//     backupPolicyName: 'DailyBackupPolicy-1AM-14Days'
//     backupTime: '01:00'
//     retentionDays: 14
//     tags: tags
//   }
//   dependsOn: [
//     resourceGroup
//   ]
// }

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
    #disable-next-line use-safe-access
    existingPublicIpId: contains(persistentIpLookup, vm.name) ? persistentIpLookup[vm.name] : ''
    dnsLabel: vm.?dnsLabel ?? ''
    useGalleryImage: !useMarketplaceImages
    galleryImageId: vm.imageDefinition == 'jumphost' ? galleryImageIdJumphost : (vm.imageDefinition == 'ubuntu' ? galleryImageIdUbuntu : galleryImageIdWindows)
    marketplacePublisher: useMarketplaceImages ? (vm.imageDefinition == 'windows' ? 'MicrosoftWindowsServer' : 'canonical') : ''
    marketplaceOffer: useMarketplaceImages ? (vm.imageDefinition == 'windows' ? 'WindowsServer' : 'ubuntu-22_04-lts') : ''
    marketplaceSku: useMarketplaceImages ? (vm.imageDefinition == 'windows' ? '2022-datacenter-azure-edition-smalldisk' : 'server') : ''
    marketplaceVersion: 'latest'
    osDiskSizeGb: vm.osDiskSizeGb
    dataDisks: vm.?dataDisks ?? []
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    deployMonitoringAgent: false // Disable to avoid package manager lock issues during deployment
    // jumphost needs MSI for Ansible auth_source: msi; all VMs need MSI when AMA is enabled
    assignManagedIdentity: vm.name == 'vm-jmp-01' || deployAMA
    // vm-jmp-01: marketplace -> bootstrap complet; gallery -> finalizare minima (auth fix)
    // Alte VM-uri Linux: fara CSE (configurate de Ansible)
    // VM-uri Windows: WinRM bootstrap (doar marketplace)
    customScriptContent: vm.name == 'vm-jmp-01'
      ? (useMarketplaceImages ? jumphostBootstrapScript : jumphostFinalizeScript)
      : (vm.osType == 'Windows' ? windowsWinrmBootstrapScript : '')
    autoShutdownTime: autoShutdownTime
    autoShutdownTimezone: autoShutdownTimezone
    tags: tags
  }
}]

// ----- Module: VM Backup Protection (Loop) -----
// DISABLED: depends on backup module which is currently commented out.

// module vmBackupProtection 'modules/backup-vm.bicep' = [for (vm, i) in vms: {
//   name: 'deploy-backup-${vm.name}'
//   scope: az.resourceGroup(resourceGroupName)
//   params: {
//     location: location
//     vaultName: backupVaultName
//     vmName: vm.name
//     vmId: virtualMachines[i].outputs.vmId
//     backupPolicyId: backup.outputs.backupPolicyId
//   }
//   dependsOn: [
//     virtualMachines
//   ]
// }]

// ----- MSI: Reader on Persistent RG (for azure_rm inventory plugin) -----
// The jumphost MSI (assigned above) needs Reader on rg-mediasrl-persistent so the
// azure_rm inventory plugin can read public IP objects referenced by VM NICs.
// Without this, the plugin logs AuthorizationFailed errors (non-fatal, but noisy).
//
// principalId is taken from the virtualMachines module output (evaluated at runtime,
// after the VM is deployed) — NOT from an 'existing' reference (evaluated at ARM
// planning time, before the RG exists, which caused ResourceGroupNotFound on fresh deploys).

var jumphostIndex = filter(range(0, length(vms)), i => vms[i].name == 'vm-jmp-01')[0]

module jumphostMsiPersistentRgReader 'modules/role-assignment.bicep' = {
  name: 'jumphost-msi-persistent-rg-reader'
  scope: az.resourceGroup(persistentResourceGroupName)
  params: {
    principalId: virtualMachines[jumphostIndex].outputs.msiPrincipalId
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    roleDescription: 'Ansible MSI: vm-jmp-01 reads persistent RG (static public IPs for inventory)'
  }
}

// ----- Access Policy: Jumphost MSI → kv-mediasrl-persistent -----
// Grants the jumphost MSI get+list on secrets so create-ansible-vault.sh
// can fetch infrastructure credentials via az keyvault secret show (MSI auth).
// Deployed as a module (not an inline resource) because main.bicep is subscription-scoped
// and child resources cannot cross scope boundaries inline.

module jumphostKvSecretRead 'modules/kv-access-policy.bicep' = {
  name: 'jumphost-kv-secret-read'
  scope: az.resourceGroup(persistentResourceGroupName)
  params: {
    keyVaultName: 'kv-mediasrl-persistent'
    tenantId: subscription().tenantId
    objectId: virtualMachines[jumphostIndex].outputs.msiPrincipalId
  }
}

// ----- Module: Azure Monitor Agent (AMA) — deployed after all VMs -----
// Installs AMA extension, creates DCRs, DCR Associations, Action Group, and Alert Rules.
// Requires Managed Identity on all VMs (enabled above when deployAMA = true).

var linuxVmNames  = map(filter(vms, vm => vm.osType == 'Linux'),  vm => vm.name)
var windowsVmNames = map(filter(vms, vm => vm.osType == 'Windows'), vm => vm.name)

module ama 'modules/ama.bicep' = if (deployAMA) {
  name: 'deploy-ama'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    location: location
    environment: environment
    linuxVmNames: linuxVmNames
    windowsVmNames: windowsVmNames
    workspaceResourceId: monitoring.outputs.workspaceResourceId
    alertEmail: alertEmail
    tags: tags
  }
  dependsOn: [virtualMachines]
}

// NOTE: Bootstrap/CSE strategy:
// - vm-jmp-01 + marketplace: scripts/bootstrap-jumphost.sh      (install complet: xRDP, Ansible, etc.)
// - vm-jmp-01 + gallery:     scripts/finalize-jumphost.sh       (auth fix: chpasswd, SSH, .xsession)
// - Windows   + orice:       bicep/scripts/windows-winrm-bootstrap.ps1 (WinRM — Sysprep il reseteaza
//                            indiferent daca imaginea vine din Packer sau marketplace)
// - Linux     + gallery:     fara CSE (Packer a baked totul, Ansible configureaza roluri)
// - Linux     + marketplace: fara CSE (configurate de Ansible de pe jumphost)

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

//1
