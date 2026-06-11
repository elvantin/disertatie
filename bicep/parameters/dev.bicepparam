// ============================================================
// Development Environment Parameters
// Mirrors prod configuration for pre-prod testing.
// Separate persistent RG (rg-mediasrl-persistent-dev) to avoid
// IP conflicts with prod (rg-mediasrl-persistent).
// Backup disabled (same as prod).
// ============================================================

using '../main.bicep'

// ----- Environment Configuration -----

param location = 'swedencentral'
param environment = 'dezvoltare'

// ----- Networking -----

param vnetAddressSpace = '10.10.0.0/20'
param subnetProdPrefix = '10.10.10.0/24'
param subnetDevPrefix = '10.10.11.0/24'
param subnetMgmtPrefix = '10.10.12.0/24'

param adminIpAddress = '82.78.49.150/32'

// ----- Azure AD Configuration -----

param tenantId = 'ac82a445-2540-4eda-a5c6-839042376d8f'
param adminObjectId = '9f286d78-d412-436b-9f1d-cdd24b456a0c'

// ----- Compute Gallery -----

// DEV: Foloseste imagini din gallery (useMarketplaceImages = false)
param useMarketplaceImages = false

param computeGalleryName = 'gal_mediasrl'
param ubuntuImageDefinition = 'imgdef-ubuntu2204'
param jumphostImageDefinition = 'imgdef-ubuntu2204-jumphost'
param windowsImageDefinition = 'imgdef-winserver2022'
param imageVersion = 'latest'  // Auto-selecteaza ultima versiune Packer din gallery

// ----- VM Authentication -----

param adminUsername = 'azureadmin'
// Secret fetched from persistent Key Vault at deployment time (never stored in plaintext).
// Requires kv-mediasrl-persistent to exist in rg-mediasrl-persistent.
// Run scripts/0-bootstrap-keyvault.ps1 once before deploying.
param adminPassword = az.getSecret('7a0255bf-d664-4920-afb0-c523b49c1908', 'rg-mediasrl-persistent', 'kv-mediasrl-persistent', 'vm-admin-password')

// ----- Persistent Public IPs (DEV-specific, separate from prod) -----
// Resource Group: rg-mediasrl-persistent-dev (survives teardown of main dev RG)
// DNS: mediasrl-dev.swedencentral.cloudapp.azure.com (diferit de prod: mediasrl.*)

param persistentResourceGroupName = 'rg-mediasrl-persistent-dev'

param persistentPublicIps = [
  {
    name: 'pip-dev-vm-jmp-01'
    vmName: 'vm-jmp-01'
    dnsLabel: ''
  }
  {
    name: 'pip-dev-vm-web-01'
    vmName: 'vm-web-01'
    dnsLabel: 'mediasrl-dev'
  }
]

// ----- VM Configurations (toate 6 VM-uri, identic cu prod) -----
// createPublicIp: false pentru toate — IP-urile publice vin din rg-mediasrl-persistent-dev

param vms = [
  {
    name: 'vm-jmp-01'
    osType: 'Linux'
    size: 'Standard_B4ls_v2'
    subnet: 'mgmt'                // snet-mgmt (10.10.12.0/24) — jumphost, nsg-mgmt
    createPublicIp: false
    imageDefinition: 'jumphost'
    osDiskSizeGb: 64
  }
  {
    name: 'vm-web-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'dev'                 // snet-dev (10.10.11.0/24) — VMs de dezvoltare, nsg-dev
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
  {
    name: 'vm-app-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'dev'                 // snet-dev (10.10.11.0/24)
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
  {
    name: 'vm-cms-01'
    osType: 'Linux'
    size: 'Standard_B2s'
    subnet: 'dev'                 // snet-dev (10.10.11.0/24)
    createPublicIp: false
    imageDefinition: 'ubuntu'
    osDiskSizeGb: 32
  }
  {
    name: 'vm-db-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'dev'                 // snet-dev (10.10.11.0/24)
    createPublicIp: false
    imageDefinition: 'windows'
    osDiskSizeGb: 128
  }
  {
    name: 'vm-fs-01'
    osType: 'Windows'
    size: 'Standard_B2s'
    subnet: 'dev'                 // snet-dev (10.10.11.0/24)
    createPublicIp: false
    imageDefinition: 'windows'
    osDiskSizeGb: 128
  }
]
