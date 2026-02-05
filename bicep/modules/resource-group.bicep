// ============================================================
// Module: Resource Group
// Creates a Resource Group with standard tags
// ============================================================

targetScope = 'subscription'

// ----- Parameters -----

@description('Resource Group name')
param resourceGroupName string

@description('Azure region for the Resource Group')
param location string

@description('Environment (prod/dev)')
@allowed([
  'prod'
  'dev'
])
param environment string

@description('Project name')
param project string = 'media'

@description('Owner')
param owner string = 'IT Security SRL'

// ----- Resource Group -----

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: {
    environment: environment
    project: project
    owner: owner
    'managed-by': 'bicep'
  }
}

// ----- Outputs -----

output resourceGroupName string = rg.name
output resourceGroupId string = rg.id
output location string = rg.location
