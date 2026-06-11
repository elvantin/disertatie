// ============================================================
// Module: Azure Backup
// Creates Recovery Services Vault and Backup Policy
// Daily backup at 1:00 AM with 14-day retention
// ============================================================

@description('Azure region for resources')
param location string

@description('Recovery Services Vault name')
param vaultName string

@description('Backup policy name')
param backupPolicyName string = 'DailyBackupPolicy'

@description('Backup schedule time (HH:MM format, 24-hour)')
param backupTime string = '01:00'

@description('Backup retention in days')
param retentionDays int = 14

@description('Resource tags')
param tags object

// ----- Recovery Services Vault -----

resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'Disabled'
      }
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Disabled'
      }
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
    }
  }
}

// ----- Backup Policy for Azure VMs -----

resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  name: backupPolicyName
  parent: recoveryServicesVault
  properties: {
    backupManagementType: 'AzureIaasVM'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2000-01-01T${backupTime}:00Z'
      ]
      scheduleWeeklyFrequency: 0
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2000-01-01T${backupTime}:00Z'
        ]
        retentionDuration: {
          count: retentionDays
          durationType: 'Days'
        }
      }
    }
    instantRpRetentionRangeInDays: 2
    timeZone: 'UTC'
  }
}

// ----- Outputs -----

output vaultId string = recoveryServicesVault.id
output vaultName string = recoveryServicesVault.name
output backupPolicyId string = backupPolicy.id
output backupPolicyName string = backupPolicy.name
