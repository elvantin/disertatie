// ============================================================
// Module: Monitoring
// Creates Log Analytics Workspace for centralized logging and monitoring
// Configured to use free tier (5 GB/month) for cost optimization
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('Log Analytics Workspace name')
param workspaceName string

@description('SKU for Log Analytics (PerGB2018 for free tier + pay-as-you-go)')
@allowed([
  'PerGB2018'
  'CapacityReservation'
])
param sku string = 'PerGB2018'

@description('Data retention period in days (31-730). Free tier includes 31 days.')
@minValue(31)
@maxValue(730)
param retentionInDays int = 31

@description('Daily quota in GB (0 = no cap, leverages 5 GB free tier)')
@minValue(0)
param dailyQuotaGb int = 0

@description('Tags to apply to resources')
param tags object = {}

// ----- Log Analytics Workspace -----

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    workspaceCapping: dailyQuotaGb > 0 ? {
      dailyQuotaGb: dailyQuotaGb
    } : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: false
    }
  }
}

// ----- Outputs -----

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output workspaceResourceId string = logAnalyticsWorkspace.id
output customerId string = logAnalyticsWorkspace.properties.customerId
