// ============================================================
// AI Monitoring Stack — Parameters
// Deploy: az deployment sub create \
//   --location swedencentral \
//   --template-file bicep/ai-monitoring.bicep \
//   --parameters bicep/parameters/ai-monitoring.bicepparam
// ============================================================

using '../ai-monitoring.bicep'

param location = 'swedencentral'

param resourceGroupName = 'rg-mediasrl-aimonitoring-swedencentral'

// Nume unice global — modifica daca sunt deja luate
param aoaiName = 'aoai-mediasrl-productie'
param functionAppName = 'func-mediasrl-logmonitor'
param storageAccountName = 'stmediasrlmonitor'
param appInsightsName = 'appi-mediasrl-logmonitor'

// Model GPT-4o
param gpt4oDeploymentName = 'gpt4o'
param gpt4oModelVersion = '2024-11-20'
param gpt4oCapacityKtpm = 10  // 10K tokens/minut — suficient pt 15min interval

// Log Analytics Workspace existent (din rg-mediasrl-productie-swedencentral)
// Obtine cu: az monitor log-analytics workspace show \
//   --resource-group rg-mediasrl-productie-swedencentral \
//   --workspace-name log-mediasrl-productie \
//   --query "{id:id, customerId:customerId}" -o json
param logAnalyticsWorkspaceId = '/subscriptions/7a0255bf-d664-4920-afb0-c523b49c1908/resourceGroups/rg-mediasrl-productie-swedencentral/providers/Microsoft.OperationalInsights/workspaces/log-mediasrl-productie'
param logAnalyticsWorkspaceCustomerId = ''  // TODO: completati cu GUID-ul din comanda de mai sus

// VM-urile monitorizate
param expectedVMs = 'vm-jmp-01,vm-web-01,vm-app-01,vm-cms-01,vm-db-01,vm-fs-01'
param queryWindowMinutes = 15
