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

param adminIpAddress = '79.119.44.61/32' // TODO: Update if IP changes (az ip show: curl https://api.ipify.org)

// ----- Azure AD Configuration -----

param tenantId = 'ac82a445-2540-4eda-a5c6-839042376d8f'
param adminObjectId = '9f286d78-d412-436b-9f1d-cdd24b456a0c'

// ----- Compute Gallery -----

// DEV: Marketplace images (faster rebuild, no dependency on Packer gallery)
// Switch to false + gallery images when ready to test Packer images in dev
param useMarketplaceImages = true

param computeGalleryName = 'gal_mediasrl'
param ubuntuImageDefinition = 'imgdef-ubuntu2204'
param jumphostImageDefinition = 'imgdef-ubuntu2204-jumphost'
param windowsImageDefinition = 'imgdef-winserver2022'
param imageVersion = '1.0.0'

// ----- Azure Backup -----
// Disabled in main.bicep (commented out) — vault name kept for reference only

param backupVaultName = 'rsv-mediasrl-dezvoltare'

// ----- VM Authentication -----

param adminUsername = 'azureadmin'
param adminPassword = 'Str0ng_P@ssw0rd_2026!' // TODO: Use secure parameter or Key Vault
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKT342/08MOWn46brpiWZWmFYYI01UwtgnY0WJ24kodPLdHPAK54EnlYgVLQNQ+NxS/68/3voNxc2J7lUCJhRuEVIDM5gu4l8BNaeoPB2n9ANDqKx/p813ssVWeD+OR/ee9HUZdZ/teo09z4HbFFZQ8BG9tAM7xsO5a9nrrLDAxEIaaJZztoRVOO7L/nr1jJMl4TIldrRuUw4pFKZ2PbJYKbEV02P+6l870QH1Z09A10Tjpt4Bf3UxWeeqjbdmjgQoM3ugVMsW1E8y74dvu5kA8ChImJITEL5bUTzoGlTwy/VwWXctNK3fGLNnFPyI18y/CqDstV5RhcgsECydpDhKiRfaM7CZhjSroUqVybmMIHvyZwqMvXOaob0aPXEzRA+Q19GGIHmwAnGEazjZQ4hvFdQO1UK3oCLGLGlbOq9LNRxFR/U+jB3bs13z0Bo9Eobgdlj3cs1b9kzGVhyU6HYt58F2+HXBXiaZFxcktj8A2CwyK3z595A3oRX9hyKFIxYo6ZnCVzoLPruSQAs+pu7ixeWXYxCG7aZ3TbBXYdwWz/idZNiaUD1HvgfE+nnrKCVFU7o+79FGag5v1udpzWECHCDnWwLgKFOPiz92ayyH49F3KKFYOtgIarJB0FHNCpeUTJ0pADPmu1c0GosfcXsOz89DQSO7PD5PFBNsNdma7Q== mediasrl-azure'

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
    size: 'Standard_D2s_v3'
    subnet: 'mgmt'
    createPublicIp: false
    imageDefinition: 'jumphost'  // marketplace: va folosi imaginea ubuntu canonical (CSE Bootstrap va configura xRDP+Ansible)
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
]
