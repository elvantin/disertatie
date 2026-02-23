// ============================================================
// Module: AI Monitoring Resources
// Resurse deployate in rg-mediasrl-aimonitoring-swedencentral:
//   - Azure OpenAI (GPT-4o deployment)
//   - Storage Account (necesar pentru Function App)
//   - App Service Plan (Consumption Y1 Linux)
//   - Function App Python 3.11 (System-assigned Managed Identity)
//   - Application Insights (workspace-based, legat de log-mediasrl-productie)
//   - Role assignments fara chei:
//       MI -> Log Analytics Reader (pe workspace)
//       MI -> Cognitive Services OpenAI User (pe AOAI)
// ============================================================

// ----- Parameters -----

param location string
param aoaiName string
param functionAppName string
param storageAccountName string
param appInsightsName string
param gpt4oDeploymentName string
param gpt4oModelVersion string
param gpt4oCapacityKtpm int
param logAnalyticsWorkspaceId string
param logAnalyticsWorkspaceCustomerId string
param expectedVMs string
param queryWindowMinutes int
param tags object

// ----- Reference existing Log Analytics Workspace -----

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  // Workspace-ul este in alt RG — referinta prin resource ID complet
  scope: resourceGroup(split(logAnalyticsWorkspaceId, '/')[2], split(logAnalyticsWorkspaceId, '/')[4])
  name: split(logAnalyticsWorkspaceId, '/')[8]
}

// ============================================================
// AZURE OPENAI
// ============================================================

resource aoai 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: aoaiName
  location: location
  kind: 'OpenAI'
  tags: tags
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: aoaiName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false // Pastram si API key ca fallback
  }
}

resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: aoai
  name: gpt4oDeploymentName
  sku: {
    name: 'Standard'
    capacity: gpt4oCapacityKtpm
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: gpt4oModelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// ============================================================
// APPLICATION INSIGHTS (workspace-based -> log-mediasrl-productie)
// ============================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================
// STORAGE ACCOUNT (necesar pentru Azure Functions runtime)
// ============================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

// ============================================================
// APP SERVICE PLAN — Consumption Y1 Linux (serverless)
// ============================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${functionAppName}'
  location: location
  kind: 'functionapp'
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Obligatoriu pentru Linux
  }
}

// ============================================================
// FUNCTION APP — Python 3.11 + Managed Identity
// ============================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      pythonVersion: '3.11'
      linuxFxVersion: 'Python|3.11'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        // Azure OpenAI — autentificare via Managed Identity (fara cheie)
        {
          name: 'AOAI_ENDPOINT'
          value: aoai.properties.endpoint
        }
        {
          name: 'AOAI_DEPLOYMENT_NAME'
          value: gpt4oDeploymentName
        }
        // Log Analytics — workspace ID pentru KQL queries
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspaceCustomerId
        }
        // VM-urile asteptate sa raporteze heartbeat
        {
          name: 'EXPECTED_VMS'
          value: expectedVMs
        }
        {
          name: 'QUERY_WINDOW_MINUTES'
          value: string(queryWindowMinutes)
        }
      ]
    }
  }
}

// ============================================================
// ROLE ASSIGNMENTS — Managed Identity fara chei hardcodate
// ============================================================

// Role: Log Analytics Reader
// Permite Function App-ului sa execute query-uri KQL pe workspace
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87d138a893'

resource roleLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspaceId, functionApp.id, logAnalyticsReaderRoleId)
  scope: logWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'func-mediasrl-logmonitor: citire KQL pe log-mediasrl-productie'
  }
}

// Role: Cognitive Services OpenAI User
// Permite apeluri catre Azure OpenAI fara API key
var cognitiveServicesOpenAIUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource roleAoaiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aoai.id, functionApp.id, cognitiveServicesOpenAIUserRoleId)
  scope: aoai
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'func-mediasrl-logmonitor: apeluri GPT-4o fara API key'
  }
}

// ============================================================
// OUTPUTS
// ============================================================

output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output aoaiEndpoint string = aoai.properties.endpoint
output aoaiName string = aoai.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output storageAccountName string = storageAccount.name
