// ============================================================
// Production Environment Parameters
// ============================================================

using '../main.bicep'

// ----- Environment Configuration -----

param location = 'swedencentral'
param environment = 'productie'

// ----- Networking -----

param vnetAddressSpace = '10.10.0.0/20'
param subnetProdPrefix = '10.10.10.0/24'
param subnetDevPrefix = '10.10.11.0/24'
param subnetMgmtPrefix = '10.10.12.0/24'

// IMPORTANT: Replace with your actual admin IP address
param adminIpAddress = '79.119.44.61/32' // TODO: Set to actual admin IP (e.g., "203.0.113.5/32")

// ----- Azure AD Configuration -----

// IMPORTANT: Replace with actual values from your Azure subscription
param tenantId = 'ac82a445-2540-4eda-a5c6-839042376d8f' // TODO: az account show --query tenantId -o tsv
param adminObjectId = '9f286d78-d412-436b-9f1d-cdd24b456a0c' // TODO: az ad signed-in-user show --query id -o tsv

// ----- Compute Gallery -----

param useMarketplaceImages = false

param computeGalleryName = 'gal_mediasrl'
param ubuntuImageDefinition = 'imgdef-ubuntu2204'
param jumphostImageDefinition = 'imgdef-ubuntu2204-jumphost'
param windowsImageDefinition = 'imgdef-winserver2022'
param imageVersion = 'latest'  // Auto-selecteaza ultima versiune Packer din gallery

// ----- VM Authentication -----

param adminUsername = 'azureadmin'

// IMPORTANT: Replace with secure values (use Key Vault references in production)
param adminPassword = 'Str0ng_P@ssw0rd_2026!' // TODO: Use secure parameter or Key Vault

// ----- Persistent Resource Group (IP-uri statice care supravietuiesc teardown-ului) -----

param persistentResourceGroupName = 'rg-mediasrl-persistent'

param persistentPublicIps = [
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

// ----- VM Configurations -----
// Note: createPublicIp is false for all VMs - public IPs come from persistent RG

param vms = [
  // === ACTIVE VMs ===
  {
    name: 'vm-jmp-01'
    osType: 'Linux'
    size: 'Standard_B4as_v2'
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
