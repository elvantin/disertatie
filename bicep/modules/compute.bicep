// ============================================================
// Module: Compute (Virtual Machine)
// Creates a single VM with NIC and optional Public IP
// Supports both Windows and Linux, marketplace or gallery images
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('VM name')
param vmName string

@description('VM size (SKU)')
param vmSize string

@description('OS type (Windows or Linux)')
@allowed([
  'Windows'
  'Linux'
])
param osType string

@description('Admin username')
param adminUsername string

@description('Admin password (Windows) or SSH public key (Linux)')
@secure()
param adminPasswordOrKey string

@description('Subnet ID where the VM NIC will be attached')
param subnetId string

@description('Create Public IP for this VM (ignored if existingPublicIpId is set)')
param createPublicIp bool = false

@description('ID of an existing Public IP to attach (from persistent RG). Takes priority over createPublicIp.')
param existingPublicIpId string = ''

@description('DNS label for Public IP (only used when creating new IP, not with existingPublicIpId)')
param dnsLabel string = ''

@description('Private IP address (leave empty for dynamic allocation)')
param privateIpAddress string = ''

@description('Use Azure Compute Gallery image (true) or Marketplace image (false)')
param useGalleryImage bool = true

@description('Azure Compute Gallery image ID (required if useGalleryImage = true)')
param galleryImageId string = ''

@description('Marketplace image publisher (required if useGalleryImage = false)')
param marketplacePublisher string = ''

@description('Marketplace image offer (required if useGalleryImage = false)')
param marketplaceOffer string = ''

@description('Marketplace image SKU (required if useGalleryImage = false)')
param marketplaceSku string = ''

@description('Marketplace image version (required if useGalleryImage = false)')
param marketplaceVersion string = 'latest'

@description('OS disk size in GB')
@minValue(30)
@maxValue(2048)
param osDiskSizeGb int = 128

@description('OS disk storage type')
@allowed([
  'Standard_LRS'
  'StandardSSD_LRS'
  'Premium_LRS'
])
param osDiskStorageType string = 'StandardSSD_LRS'

@description('Log Analytics Workspace ID for VM monitoring')
param logAnalyticsWorkspaceId string = ''

@description('Deploy Log Analytics agent extension (disable to avoid package manager lock issues)')
param deployMonitoringAgent bool = false

@description('Custom script to execute after VM creation (raw text, empty = skip)')
param customScriptContent string = ''

@description('Assign System-Assigned Managed Identity to this VM (used by jumphost for Ansible MSI auth)')
param assignManagedIdentity bool = false

@description('Data disks to attach (array of {lun, diskSizeGB, storageType}). Empty = no data disks.')
param dataDisks array = []

@description('Auto-shutdown time in HHMM format (e.g. "2359"). Empty string = disabled.')
param autoShutdownTime string = ''

@description('Timezone for auto-shutdown schedule')
param autoShutdownTimezone string = 'E. Europe Standard Time'

@description('Tags to apply to resources')
param tags object = {}

// ----- Variables -----

var nicName = 'nic-${vmName}'
var pipName = 'pip-${vmName}'
var osDiskName = 'osdisk-${vmName}'
var linuxConfiguration = {
  disablePasswordAuthentication: false
  // SSH keys will be configured via Ansible after deployment
  // (jumphost generates keys and distributes to other Linux VMs)
}

// ----- Public IP (only if creating new, not when using existing from persistent RG) -----

var useExistingPip = existingPublicIpId != ''
var shouldCreatePip = createPublicIp && !useExistingPip

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (shouldCreatePip) {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: dnsLabel != '' ? {
      domainNameLabel: dnsLabel
    } : null
  }
}

// ----- Network Interface -----

// Determine which public IP to attach (existing from persistent RG, newly created, or none)
var publicIpConfig = useExistingPip ? {
  id: existingPublicIpId
} : shouldCreatePip ? {
  id: publicIp.id
} : null

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: privateIpAddress != '' ? 'Static' : 'Dynamic'
          privateIPAddress: privateIpAddress != '' ? privateIpAddress : null
          publicIPAddress: publicIpConfig
        }
      }
    ]
  }
}

// ----- Virtual Machine -----

// Built-in Reader role — allows MSI to enumerate Azure resources for Ansible dynamic inventory
var readerRoleDefinitionId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  identity: assignManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  // Plan information is only needed for specific marketplace images (not Windows Server or Ubuntu/Canonical)
  plan: !useGalleryImage && marketplacePublisher != 'MicrosoftWindowsServer' && marketplacePublisher != 'canonical' ? {
    name: marketplaceSku
    publisher: marketplacePublisher
    product: marketplaceOffer
  } : null
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: useGalleryImage ? {
        id: galleryImageId
      } : {
        publisher: marketplacePublisher
        offer: marketplaceOffer
        sku: marketplaceSku
        version: marketplaceVersion
      }
      osDisk: {
        name: osDiskName
        createOption: 'FromImage'
        deleteOption: 'Delete'
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: osDiskStorageType
        }
        caching: 'ReadWrite'
      }
      dataDisks: [for (disk, i) in dataDisks: {
        lun: disk.lun
        name: 'datadisk-${vmName}-${disk.lun}'
        createOption: 'Empty'
        diskSizeGB: disk.diskSizeGB
        managedDisk: {
          storageAccountType: disk.?storageType ?? 'StandardSSD_LRS'
        }
        caching: 'None'
      }]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: osType == 'Linux' ? linuxConfiguration : null
      windowsConfiguration: osType == 'Windows' ? {
        enableAutomaticUpdates: !useGalleryImage
        provisionVMAgent: true
        patchSettings: {
          patchMode: useGalleryImage ? 'Manual' : 'AutomaticByPlatform'
          automaticByPlatformSettings: !useGalleryImage ? {
            rebootSetting: 'IfRequired'
          } : null
        }
      } : null
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// ----- VM Extension: Log Analytics Agent (optional) -----

resource vmExtensionMmaWindows 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (osType == 'Windows' && logAnalyticsWorkspaceId != '' && deployMonitoringAgent) {
  parent: vm
  name: 'MicrosoftMonitoringAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.EnterpriseCloud.Monitoring'
    type: 'MicrosoftMonitoringAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      workspaceId: reference(logAnalyticsWorkspaceId, '2023-09-01').customerId
    }
    protectedSettings: {
      workspaceKey: listKeys(logAnalyticsWorkspaceId, '2023-09-01').primarySharedKey
    }
  }
}

resource vmExtensionOmsLinux 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (osType == 'Linux' && logAnalyticsWorkspaceId != '' && deployMonitoringAgent) {
  parent: vm
  name: 'OmsAgentForLinux'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.EnterpriseCloud.Monitoring'
    type: 'OmsAgentForLinux'
    typeHandlerVersion: '1.14'
    autoUpgradeMinorVersion: true
    settings: {
      workspaceId: reference(logAnalyticsWorkspaceId, '2023-09-01').customerId
    }
    protectedSettings: {
      workspaceKey: listKeys(logAnalyticsWorkspaceId, '2023-09-01').primarySharedKey
    }
  }
}

// ----- VM Extension: Custom Script (Linux) -----

resource customScriptLinux 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (osType == 'Linux' && customScriptContent != '') {
  parent: vm
  name: 'CustomScript'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      script: base64(customScriptContent)
    }
  }
}

// ----- VM Run Command: WinRM Bootstrap (Windows) -----
// runCommands accepts the script content directly — no cmd.exe command-line length limit.
// Custom Script Extension (CSE) was replaced because the base64-encoded script exceeded
// the 8191-char cmd.exe limit when passed via commandToExecute.

resource winrmRunCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = if (osType == 'Windows' && customScriptContent != '') {
  parent: vm
  name: 'WinRMBootstrap'
  location: location
  tags: tags
  properties: {
    source: {
      script: customScriptContent
    }
    asyncExecution: false
    timeoutInSeconds: 600
  }
}

// ----- Role Assignment: Reader on resource group (only when MSI is assigned) -----
// Grants the VM's managed identity read access to all resources in the RG.
// Required for Ansible azure_rm inventory plugin with auth_source: msi.

// Role assignment names are deterministic (RG + vmName + roleId).
// Orphaned assignments (left after VM deletion) are cleaned up by 2-deploy-teardown-bicep.ps1
// before each deploy, avoiding RoleAssignmentUpdateNotPermitted on VM recreate.

resource roleAssignmentReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignManagedIdentity) {
  name: guid(resourceGroup().id, vmName, readerRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleDefinitionId)
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Ansible MSI: ${vmName} reads Azure resources in this RG (dynamic inventory)'
  }
}

// Virtual Machine Contributor — needed for az vm run-command invoke (SSH key injection playbook)
var vmContributorRoleDefinitionId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource roleAssignmentVmContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignManagedIdentity) {
  name: guid(resourceGroup().id, vmName, vmContributorRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleDefinitionId)
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Ansible MSI: ${vmName} manages VMs in this RG (run-command, SSH key injection)'
  }
}

// Network Contributor — needed for az network nsg rule update
// Used by certbot-letsencrypt.sh to temporarily open port 80 for HTTP-01 challenge
var networkContributorRoleDefinitionId = '4d97b98b-1d4f-4787-a291-c67834d212e7'

resource roleAssignmentNetworkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignManagedIdentity) {
  name: guid(resourceGroup().id, vmName, networkContributorRoleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleDefinitionId)
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Ansible MSI: ${vmName} manages network resources in this RG (NSG rules for certbot)'
  }
}

// ----- Auto-shutdown Schedule -----

resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (autoShutdownTime != '') {
  name: 'shutdown-computevm-${vmName}'
  location: location
  tags: tags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimezone
    targetResourceId: vm.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

// ----- Outputs -----

output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress

// Safe-access operator (.?) handles conditional resource — returns '' when publicIp doesn't exist
@description('Public IP address (empty if no public IP was created)')
output publicIpAddress string = publicIp.?properties.?ipAddress ?? ''

// ARM if() is lazy — vm.identity.principalId is only evaluated when assignManagedIdentity = true
output msiPrincipalId string = assignManagedIdentity ? vm.identity.principalId : ''
