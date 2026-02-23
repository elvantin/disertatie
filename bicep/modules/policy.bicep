// ============================================================
// Module: Azure Policy
// Assigns governance policies to enforce compliance and best practices
// ============================================================

targetScope = 'subscription'

// ----- Parameters -----

@description('Allowed Azure regions for resources')
param allowedLocations array = [
  'westeurope'
  'northeurope'
]

// ----- Policy Assignment: Allowed Locations -----

resource policyAllowedLocations 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-allowed-locations'
  properties: {
    displayName: 'Allowed Azure Regions'
    description: 'Restricts resource deployment to approved Azure regions (West Europe, North Europe)'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
    parameters: {
      listOfAllowedLocations: {
        value: allowedLocations
      }
    }
  }
}

// ----- Policy Assignment: Require Tag (environment) -----

resource policyRequireTagEnvironment 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-require-tag-env'
  properties: {
    displayName: 'Require Tag: environment'
    description: 'Enforces the presence of the "environment" tag on all resources'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
    parameters: {
      tagName: {
        value: 'environment'
      }
    }
  }
}

// ----- Policy Assignment: Require Tag (project) -----

resource policyRequireTagProject 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-require-tag-project'
  properties: {
    displayName: 'Require Tag: project'
    description: 'Enforces the presence of the "project" tag on all resources'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
    parameters: {
      tagName: {
        value: 'project'
      }
    }
  }
}

// ----- Policy Assignment: Require Tag (managed-by) -----

resource policyRequireTagManagedBy 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-require-tag-mgmt'
  properties: {
    displayName: 'Require Tag: managed-by'
    description: 'Enforces the presence of the "managed-by" tag on all resources'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99'
    parameters: {
      tagName: {
        value: 'managed-by'
      }
    }
  }
}

// ----- Policy Assignment: Allowed VM SKUs (cost control) -----

resource policyAllowedVmSkus 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-allowed-vm-skus'
  properties: {
    displayName: 'Allowed VM SKUs'
    description: 'Restricts VM deployments to approved SKUs (B-series, D-series) for cost control'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/cccc23c7-8427-4f53-ad12-b6a63eb452b3'
    parameters: {
      listOfAllowedSKUs: {
        value: [
          'Standard_B1s'
          'Standard_B1ms'
          'Standard_B2s'
          'Standard_B2ms'
          'Standard_B4ms'
          'Standard_B2s_v2'
          'Standard_B2as_v2'
          'Standard_B2als_v2'
          'Standard_B4s_v2'
          'Standard_B4as_v2'
          'Standard_D2s_v3'
          'Standard_D4s_v3'
        ]
      }
    }
  }
}

// ----- Policy Assignment: Audit VMs without Managed Disks -----

resource policyAuditUnmanagedDisks 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'policy-audit-unmanaged-disks'
  properties: {
    displayName: 'Audit VMs without Managed Disks'
    description: 'Audits VMs that do not use Azure Managed Disks'
    enforcementMode: 'Default'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/06a78e20-9358-41c9-923c-fb736d382a4d'
    parameters: {}
  }
}

// ----- Outputs -----

output policyAllowedLocationsId string = policyAllowedLocations.id
output policyRequireTagEnvironmentId string = policyRequireTagEnvironment.id
output policyRequireTagProjectId string = policyRequireTagProject.id
output policyRequireTagManagedById string = policyRequireTagManagedBy.id
output policyAllowedVmSkusId string = policyAllowedVmSkus.id
output policyAuditUnmanagedDisksId string = policyAuditUnmanagedDisks.id
