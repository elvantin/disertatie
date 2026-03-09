// ============================================================
// Module: Network Security Groups (NSGs)
// Creates NSGs for mgmt, prod, and dev subnets with CIS-aligned rules
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('Admin IP address for RDP access to jumphost (CIDR notation, e.g., "1.2.3.4/32")')
param adminIpAddress string

@description('Tags to apply to resources')
param tags object = {}

// ----- NSG: Management Subnet (snet-mgmt) -----

resource nsgMgmt 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-mgmt'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Admin'
        properties: {
          description: 'Allow RDP to jumphost from admin IP only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: adminIpAddress
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH-From-Admin'
        properties: {
          description: 'Allow SSH to jumphost from admin IP only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: adminIpAddress
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 200
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ----- NSG: Production Subnet (snet-prod) -----

resource nsgProd 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-prod'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Jumphost'
        properties: {
          description: 'Allow RDP from jumphost to Windows VMs'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH-From-Jumphost'
        properties: {
          description: 'Allow SSH from jumphost to Linux VMs'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-WinRM-From-Jumphost'
        properties: {
          description: 'Allow WinRM HTTP from jumphost to Windows VMs (Ansible)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5985'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 115
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS-To-Web'
        properties: {
          description: 'Allow HTTPS from any source to web server (primary traffic)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTP-To-Web'
        properties: {
          // Port 80 restricted to VNet CIDR (10.10.0.0/20) — internal traffic only.
          // Let's Encrypt renewal uses DNS-01 challenge (no public port 80 needed).
          // HTTP → HTTPS redirect is handled by nginx for internal/VNet traffic.
          description: 'Allow HTTP from VNet only (internal traffic + HTTP->HTTPS redirect)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 121
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-MySQL-Internal'
        properties: {
          description: 'Allow MySQL from VNet CIDR 10.10.0.0/20 (prod subnet + jumphost in mgmt subnet)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SMTP-Internal'
        properties: {
          description: 'Allow SMTP from VNet CIDR 10.10.0.0/20 (prod subnet + jumphost in mgmt subnet)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '25'
            '587'
          ]
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 210
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-AppServer-Internal'
        properties: {
          description: 'Allow port 8080 from VNet CIDR 10.10.0.0/20 (nginx reverse proxy -> vm-app-01 API)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 220
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SMB-Internal'
        properties: {
          description: 'Allow SMB from VNet CIDR 10.10.0.0/20 (file server access from all subnets)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '445'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.10.0/24'
          access: 'Allow'
          priority: 225
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 300
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ----- NSG: Development Subnet (snet-dev) -----
// Reguli identice cu nsg-prod, adaptate pentru snet-dev (10.10.11.0/24).

resource nsgDev 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-dev'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-From-Jumphost'
        properties: {
          description: 'Allow RDP from jumphost to Windows VMs in dev subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH-From-Jumphost'
        properties: {
          description: 'Allow SSH from jumphost to Linux VMs in dev subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-WinRM-From-Jumphost'
        properties: {
          description: 'Allow WinRM HTTP from jumphost to Windows VMs in dev (Ansible)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5985'
          sourceAddressPrefix: '10.10.12.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 115
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS-To-Web'
        properties: {
          description: 'Allow HTTPS from any source to web server in dev subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTP-To-Web'
        properties: {
          description: 'Allow HTTP from VNet only (internal traffic + HTTP->HTTPS redirect)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 121
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-MySQL-Internal'
        properties: {
          description: 'Allow MySQL from VNet CIDR 10.10.0.0/20 (dev subnet + jumphost in mgmt subnet)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SMTP-Internal'
        properties: {
          description: 'Allow SMTP from VNet CIDR 10.10.0.0/20 (dev subnet + jumphost in mgmt subnet)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '25'
            '587'
          ]
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 210
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-AppServer-Internal'
        properties: {
          description: 'Allow port 8080 from VNet CIDR 10.10.0.0/20 (nginx -> vm-app-01 API)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 220
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SMB-Internal'
        properties: {
          description: 'Allow SMB from VNet CIDR 10.10.0.0/20 (file server access from all subnets)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '445'
          sourceAddressPrefix: '10.10.0.0/20'
          destinationAddressPrefix: '10.10.11.0/24'
          access: 'Allow'
          priority: 225
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 300
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ----- Outputs -----

output nsgMgmtId string = nsgMgmt.id
output nsgMgmtName string = nsgMgmt.name

output nsgProdId string = nsgProd.id
output nsgProdName string = nsgProd.name

output nsgDevId string = nsgDev.id
output nsgDevName string = nsgDev.name
