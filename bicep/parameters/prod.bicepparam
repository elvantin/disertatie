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
param adminIpAddress = '0.0.0.0/32' // TODO: Set to actual admin IP (e.g., "203.0.113.5/32")

// ----- Azure AD Configuration -----

// IMPORTANT: Replace with actual values from your Azure subscription
param tenantId = '00000000-0000-0000-0000-000000000000' // TODO: az account show --query tenantId -o tsv
param adminObjectId = '00000000-0000-0000-0000-000000000000' // TODO: az ad signed-in-user show --query id -o tsv

// ----- Compute Gallery -----

param computeGalleryName = 'gal_mediasrl'
param rockyImageDefinition = 'imgdef-rockylinux10'
param windowsImageDefinition = 'imgdef-winserver2022'
param imageVersion = '1.0.0'

// ----- VM Authentication -----

param adminUsername = 'azureadmin'

// IMPORTANT: Replace with secure values (use Key Vault references in production)
param adminPassword = 'CHANGE_ME_P@ssw0rd123!' // TODO: Use secure parameter or Key Vault
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...' // TODO: Replace with actual SSH public key

// ----- VM Configurations -----

param vms = [
  {
    name: 'vm-jmp-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'mgmt'
    createPublicIp: true
    imageDefinition: 'windows'
  }
  {
    name: 'vm-db-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'windows'
  }
  {
    name: 'vm-web-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'rocky'
  }
  {
    name: 'vm-app-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'rocky'
  }
  {
    name: 'vm-cms-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'prod'
    createPublicIp: false
    imageDefinition: 'rocky'
  }
]
