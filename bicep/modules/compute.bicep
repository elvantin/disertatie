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

@description('Create Public IP for this VM')
param createPublicIp bool = false

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

// ----- Public IP (conditional) -----

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (createPublicIp) {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// ----- Network Interface -----

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
          publicIPAddress: createPublicIp ? {
            id: publicIp.id
          } : null
        }
      }
    ]
  }
}

// ----- Virtual Machine -----

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
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
        diskSizeGB: osDiskSizeGb
        managedDisk: {
          storageAccountType: osDiskStorageType
        }
        caching: 'ReadWrite'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPasswordOrKey
      linuxConfiguration: osType == 'Linux' ? linuxConfiguration : null
      windowsConfiguration: osType == 'Windows' ? {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            rebootSetting: 'IfRequired'
          }
        }
      } : null
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
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

// ----- Outputs -----

output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress

// Conditional output for public IP (avoid BCP318 warning by using resource condition)
@description('Public IP address (empty if createPublicIp = false)')
output publicIpAddress string = createPublicIp ? publicIp.properties.ipAddress : ''
