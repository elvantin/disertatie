// ============================================================
// Module: Persistent Public IPs
// Deployed in a separate resource group that survives environment
// teardowns (az group delete on the main RG won't affect these)
// ============================================================

@description('Azure region')
param location string

@description('Tags')
param tags object = {}

@description('Public IP configurations')
param publicIps array

// ----- Public IPs -----

resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for ip in publicIps: {
  name: ip.name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: ip.?dnsLabel != null && ip.?dnsLabel != '' ? {
      domainNameLabel: ip.dnsLabel
    } : null
  }
}]

// ----- Outputs -----

output publicIpIds array = [for (ip, i) in publicIps: {
  name: ip.name
  vmName: ip.vmName
  id: pip[i].id
  ipAddress: pip[i].properties.ipAddress
  fqdn: ip.?dnsLabel != null && ip.?dnsLabel != '' ? pip[i].properties.dnsSettings.fqdn : ''
}]
