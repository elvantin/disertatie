// ============================================================
// Module: Networking
// Creates VNet, Subnets, and Route Tables
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('VNet name')
param vnetName string

@description('VNet address space (CIDR)')
param vnetAddressSpace string

@description('Production subnet name')
param subnetProdName string

@description('Production subnet address prefix (CIDR)')
param subnetProdPrefix string

@description('Development subnet name')
param subnetDevName string

@description('Development subnet address prefix (CIDR)')
param subnetDevPrefix string

@description('Management subnet name')
param subnetMgmtName string

@description('Management subnet address prefix (CIDR)')
param subnetMgmtPrefix string

@description('NSG ID for production subnet')
param nsgProdId string

@description('NSG ID for development subnet')
param nsgDevId string

@description('NSG ID for management subnet')
param nsgMgmtId string

@description('Tags to apply to resources')
param tags object = {}

// ----- Virtual Network -----

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: subnetProdName
        properties: {
          addressPrefix: subnetProdPrefix
          networkSecurityGroup: {
            id: nsgProdId
          }
          routeTable: {
            id: routeTableProd.id
          }
        }
      }
      {
        name: subnetDevName
        properties: {
          addressPrefix: subnetDevPrefix
          networkSecurityGroup: {
            id: nsgDevId
          }
          routeTable: {
            id: routeTableDev.id
          }
        }
      }
      {
        name: subnetMgmtName
        properties: {
          addressPrefix: subnetMgmtPrefix
          networkSecurityGroup: {
            id: nsgMgmtId
          }
          routeTable: {
            id: routeTableMgmt.id
          }
        }
      }
    ]
  }
}

// ----- Route Tables -----

resource routeTableProd 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'rt-prod'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'Default-Internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}

resource routeTableDev 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'rt-dev'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'Default-Internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}

resource routeTableMgmt 'Microsoft.Network/routeTables@2023-09-01' = {
  name: 'rt-mgmt'
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'Default-Internet'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'Internet'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}

// ----- Outputs -----

output vnetId string = vnet.id
output vnetName string = vnet.name

output subnetProdId string = vnet.properties.subnets[0].id
output subnetProdName string = vnet.properties.subnets[0].name

output subnetDevId string = vnet.properties.subnets[1].id
output subnetDevName string = vnet.properties.subnets[1].name

output subnetMgmtId string = vnet.properties.subnets[2].id
output subnetMgmtName string = vnet.properties.subnets[2].name

output routeTableProdId string = routeTableProd.id
output routeTableDevId string = routeTableDev.id
output routeTableMgmtId string = routeTableMgmt.id
