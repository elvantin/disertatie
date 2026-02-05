// ============================================================
// Development Environment Parameters
// ============================================================

using '../main.bicep'

// ----- Environment Configuration -----

param location = 'swedencentral'
param environment = 'dezvoltare'

// ----- Networking -----

param vnetAddressSpace = '10.10.0.0/20'
param subnetProdPrefix = '10.10.10.0/24' // Reusing same CIDR for dev (different VNet)
param subnetDevPrefix = '10.10.11.0/24'
param subnetMgmtPrefix = '10.10.12.0/24'

// IMPORTANT: Replace with your actual admin IP address
param adminIpAddress = '0.0.0.0/32' // TODO: Set to actual admin IP

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

// IMPORTANT: Replace with secure values
param adminPassword = 'CHANGE_ME_P@ssw0rd123!' // TODO: Use secure parameter or Key Vault
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC...' // TODO: Replace with actual SSH public key

// ----- VM Configurations (minimal for dev) -----

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
    name: 'vm-web-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'dev'
    createPublicIp: false
    imageDefinition: 'rocky'
  }
]
