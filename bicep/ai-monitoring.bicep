// ============================================================
// AI Monitoring Stack — SC MEDIA SRL
// Deploy: Azure OpenAI (GPT-4o) + Azure Function App (Python)
//         + Application Insights + Storage Account
//
// Functia ruleaza la 15 minute, interogheaza Log Analytics
// cu KQL si trimite datele catre GPT-4o pentru analiza.
// Rezultatele sunt stocate in Application Insights (Log Analytics).
//
// Autentificare fara chei: Managed Identity pe tot stack-ul.
// ============================================================

targetScope = 'subscription'

// ----- Parameters -----

@description('Azure region')
param location string = 'swedencentral'

@description('Resource Group pentru AI Monitoring (nou, separat de prod)')
param resourceGroupName string = 'rg-mediasrl-aimonitoring-swedencentral'

@description('Nume resursa Azure OpenAI (trebuie sa fie unic global)')
param aoaiName string = 'aoai-mediasrl-productie'

@description('Nume Function App (trebuie sa fie unic global)')
param functionAppName string = 'func-mediasrl-logmonitor'

@description('Nume Storage Account (3-24 chars, lowercase, unic global)')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stmediasrlmonitor'

@description('Nume Application Insights')
param appInsightsName string = 'appi-mediasrl-logmonitor'

@description('Numele deployment-ului GPT-4o in AOAI')
param gpt4oDeploymentName string = 'gpt4o'

@description('Versiunea modelului GPT-4o')
param gpt4oModelVersion string = '2024-11-20'

@description('Capacitate GPT-4o in mii de tokens/minut (TPM)')
@minValue(1)
@maxValue(450)
param gpt4oCapacityKtpm int = 10

@description('ID-ul workspace-ului Log Analytics existent (din RG productie)')
param logAnalyticsWorkspaceId string

@description('Customer ID (GUID) al workspace-ului Log Analytics')
param logAnalyticsWorkspaceCustomerId string

@description('VM-urile monitorizate (CSV)')
param expectedVMs string = 'vm-jmp-01,vm-web-01,vm-app-01,vm-cms-01,vm-db-01,vm-fs-01'

@description('Intervalul de interogare in minute (trebuie sa corespunda cu schedule-ul functiei)')
param queryWindowMinutes int = 15

param tags object = {
  project: 'mediasrl'
  environment: 'productie'
  component: 'ai-monitoring'
  'managed-by': 'bicep'
}

// ----- Resource Group -----

resource aiMonitoringRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ----- Module deployment -----

module aiStack 'modules/ai-monitoring-resources.bicep' = {
  name: 'aiMonitoringStack'
  scope: aiMonitoringRg
  params: {
    location: location
    aoaiName: aoaiName
    functionAppName: functionAppName
    storageAccountName: storageAccountName
    appInsightsName: appInsightsName
    gpt4oDeploymentName: gpt4oDeploymentName
    gpt4oModelVersion: gpt4oModelVersion
    gpt4oCapacityKtpm: gpt4oCapacityKtpm
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    logAnalyticsWorkspaceCustomerId: logAnalyticsWorkspaceCustomerId
    expectedVMs: expectedVMs
    queryWindowMinutes: queryWindowMinutes
    tags: tags
  }
}

// ----- Outputs -----

output resourceGroupName string = aiMonitoringRg.name
output functionAppName string = aiStack.outputs.functionAppName
output aoaiEndpoint string = aiStack.outputs.aoaiEndpoint
output appInsightsConnectionString string = aiStack.outputs.appInsightsConnectionString
output functionAppPrincipalId string = aiStack.outputs.functionAppPrincipalId
