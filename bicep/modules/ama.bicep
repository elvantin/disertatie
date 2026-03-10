// ============================================================
// Module: Azure Monitor Agent (AMA) — SC MEDIA SRL
// Deploys:
//   - AMA extensions on all VMs (Linux + Windows)
//   - Data Collection Rules (DCR) for Syslog + Windows Events
//   - DCR Associations (one per VM)
//   - Action Group (email alerts)
//   - 6 Scheduled Query Alert Rules (KQL)
// Requires SystemAssigned Managed Identity on all VMs.
// ============================================================

// ----- Parameters -----

@description('Azure region')
param location string

@description('Environment (productie/dezvoltare)')
param environment string

@description('Linux VM names to install AMA on and associate with DCR')
param linuxVmNames array = []

@description('Windows VM names to install AMA on and associate with DCR')
param windowsVmNames array = []

@description('Log Analytics Workspace full resource ID')
param workspaceResourceId string

@description('Alert notification email address')
param alertEmail string

@description('Tags to apply to resources')
param tags object = {}

// ----- Existing VM references -----

resource linuxVms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for name in linuxVmNames: {
  name: name
}]

resource windowsVms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for name in windowsVmNames: {
  name: name
}]

// ----- AMA Extension: Linux -----

resource amaLinux 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for (name, i) in linuxVmNames: {
  parent: linuxVms[i]
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    // No explicit settings needed — AMA auto-discovers SystemAssigned MSI
  }
}]

// ----- AMA Extension: Windows -----

resource amaWindows 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for (name, i) in windowsVmNames: {
  parent: windowsVms[i]
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}]

// ============================================================
// Data Collection Rules (DCR)
// ============================================================

// ----- DCR: Linux Syslog -----
// Collects auth/daemon/syslog facilities at all severity levels.
// Health script writes via: logger -t mediasrl-health "ALERT CPU=95%"

resource dcrLinux 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-linux-mediasrl-${environment}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      syslog: [
        {
          name: 'syslogSecurityAndHealth'
          streams: ['Microsoft-Syslog']
          facilityNames: ['auth', 'authpriv', 'daemon', 'syslog', 'user', 'kern']
          logLevels: ['Debug', 'Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'lawDestination'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Syslog']
        destinations: ['lawDestination']
      }
    ]
  }
}

// ----- DCR: Windows Event Log -----
// Collects Security events (logon/logoff/failures) and System events (service failures).

resource dcrWindows 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-windows-mediasrl-${environment}'
  location: location
  tags: tags
  kind: 'Windows'
  properties: {
    dataSources: {
      windowsEventLogs: [
        {
          name: 'securityEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            // Logon success (4624), logon failure (4625), logoff (4634)
            'Security!*[System[(EventID=4624 or EventID=4625 or EventID=4634)]]'
          ]
        }
        {
          name: 'systemEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            // Service failures (7034=unexpected termination, 7036=state change), system errors
            'System!*[System[(EventID=7034 or EventID=7036) or (Level=1 or Level=2)]]'
          ]
        }
        {
          // Health check script (check-health.ps1) logs here.
          // Warning (Level=3) = ALERT; Error (Level=2) = critical failure.
          name: 'appHealthEvents'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[Provider[@Name=\'mediasrl-health\'] and (Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'lawDestination'
          workspaceResourceId: workspaceResourceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Event']
        destinations: ['lawDestination']
      }
    ]
  }
}

// ============================================================
// DCR Associations
// ============================================================

// ----- Linux VMs → Syslog DCR -----

resource dcrAssocLinux 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for (name, i) in linuxVmNames: {
  name: 'assoc-syslog-${environment}'
  scope: linuxVms[i]
  properties: {
    description: 'Syslog collection for mediasrl health monitoring'
    dataCollectionRuleId: dcrLinux.id
  }
  dependsOn: [amaLinux]
}]

// ----- Windows VMs → Event Log DCR -----

resource dcrAssocWindows 'Microsoft.Insights/dataCollectionRuleAssociations@2022-06-01' = [for (name, i) in windowsVmNames: {
  name: 'assoc-events-${environment}'
  scope: windowsVms[i]
  properties: {
    description: 'Windows Event Log collection for mediasrl health monitoring'
    dataCollectionRuleId: dcrWindows.id
  }
  dependsOn: [amaWindows]
}]

// ============================================================
// Action Group — email alerts to admin
// ============================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-mediasrl-${environment}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'MediaSRL'
    enabled: true
    emailReceivers: [
      {
        name: 'AdminEmail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ============================================================
// Scheduled Query Alert Rules (KQL-based)
// Toate regulile includ dimensiunea Computer — fiecare VM
// genereaza o alerta separata cu numele sau in subiect.
// Praguri ajustate pentru a evita false positives.
// ============================================================

// Alert Rule 1: SSH Brute Force Detection (Linux)
// >= 5 autentificari esuate de la acelasi IP in 15 minute.
// faillock blocheaza contul dupa 10 incercari — alerta la 5 pentru detectie timpurie.

resource alertSshBruteForce 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-ssh-brute-force-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] SSH Brute Force Detection'
    description: 'Atac brute force SSH: >= 5 autentificari esuate de la acelasi IP in 15 min. VM afectat: vezi Dimensions → Computer din email.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Syslog
| where Facility in ("auth", "authpriv")
| where SyslogMessage has "Failed password" or SyslogMessage has "Invalid user"
| extend SrcIP = extract(@"from\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", 1, SyslogMessage)
| where isnotempty(SrcIP)
| summarize FailedAttempts = count() by SrcIP, Computer, bin(TimeGenerated, 15m)
| where FailedAttempts >= 5
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT30M'
    autoMitigate: false
  }
}

// Alert Rule 2: Service/Port Down — Linux
// Confirmat jos >= 5 min: 2 evaluari consecutive cu ALERT SERVICE/PORT.
// Cron ruleaza la fiecare 5 min => 2 citiri = serviciu down cel putin 5 min.

resource alertServiceDown 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-service-down-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] Service/Port Down — Linux'
    description: 'Serviciu sau port critic inactiv >= 5 min (nginx, php-fpm, postfix, sshd). VM afectat: vezi Dimensions → Computer din email.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Syslog
| where ProcessName == "mediasrl-health"
| where SyslogMessage has "ALERT"
| where SyslogMessage has "SERVICE" or SyslogMessage has "PORT"
| project TimeGenerated, Computer, SyslogMessage
| extend Resource = extract(@"(SERVICE|PORT)=(\S+)", 2, SyslogMessage)
| extend Status   = extract(@"STATUS=(\S+)", 1, SyslogMessage)
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT15M'
    autoMitigate: false
  }
}

// Alert Rule 3: High CPU — Linux
// CPU >= 85% in cel putin 2 din 3 evaluari consecutive (≥10 min sustinut).
// Ignoram spike-uri momentane de incarcare.

resource alertHighCpu 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-high-cpu-linux-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] High CPU — Linux'
    description: 'CPU >= 85% sustinut >= 10 min (2 din 3 evaluari consecutive). VM afectat: vezi Dimensions → Computer din email.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Syslog
| where ProcessName == "mediasrl-health"
| where SyslogMessage has "ALERT" and SyslogMessage has "CPU"
| project TimeGenerated, Computer, SyslogMessage
| extend CpuPct = toint(extract(@"CPU=(\d+)", 1, SyslogMessage))
| where CpuPct >= 85
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 3
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT15M'
    autoMitigate: false
  }
}

// Alert Rule 4: Disk Space Critical — Linux
// Disk >= 90% confirmat in 2 evaluari consecutive (citire gresita exclusa).

resource alertDiskFull 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-disk-full-linux-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] Disk Space Critical — Linux'
    description: 'Spatiu disk >= 90% confirmat pe {Computer} (2 citiri consecutive).'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Syslog
| where ProcessName == "mediasrl-health"
| where SyslogMessage has "ALERT" and SyslogMessage has "DISK"
| project TimeGenerated, Computer, SyslogMessage
| extend DiskPct = toint(extract(@"DISK=(\d+)", 1, SyslogMessage))
| extend DiskPath = extract(@"PATH=(\S+)", 1, SyslogMessage)
| where DiskPct >= 90
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT30M'
    autoMitigate: false
  }
}

// Alert Rule 5: Windows Logon Brute Force
// >= 10 autentificari esuate (EventID 4625) de la acelasi IP in 10 minute.

resource alertWindowsBruteForce 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-windows-brute-force-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] Windows Logon Brute Force'
    description: 'Atac brute force RDP/Windows: >= 10 autentificari esuate (EventID 4625) in 10 min. VM afectat: vezi Dimensions → Computer din email.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Event
| where EventLog == "Security"
| where EventID == 4625
| extend SrcIP = extract(@"Source Network Address:\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})", 1, RenderedDescription)
| where isnotempty(SrcIP) and SrcIP != "-" and SrcIP != "127.0.0.1"
| summarize FailedLogins = count() by SrcIP, Computer, bin(TimeGenerated, 10m)
| where FailedLogins >= 10
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT30M'
    autoMitigate: false
  }
}

// Alert Rule 6: Windows Health Alert — Service/Port/MySQL/SMB
// Confirmat jos >= 5 min: 2 evaluari consecutive cu ALERT.
// Acoperire: vm-db-01 (MySQL80, port 3306, mysqladmin ping)
//            vm-fs-01 (LanmanServer, port 445, SMB shares)

resource alertWindowsHealth 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-windows-health-${environment}'
  location: location
  tags: tags
  properties: {
    displayName: '[MediaSRL] Windows Health Alert — Service/Port/MySQL/SMB'
    description: 'Serviciu, port, MySQL sau SMB in stare critica >= 5 min. VM afectat: vezi Dimensions → Computer din email.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: '''
Event
| where EventLog == "Application"
| where Source == "mediasrl-health"
| where EventLevelName in ("Warning", "Error")
| where RenderedDescription has "ALERT"
| project TimeGenerated, Computer, EventID, EventLevelName, RenderedDescription
| extend Resource = extract(@"(SERVICE|PORT|MYSQL|SMB[_A-Z]*)=(\S+)", 2, RenderedDescription)
| extend Status   = extract(@"STATUS=(\S+)", 1, RenderedDescription)
'''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroup.id]
      customProperties: {}
    }
    muteActionsDuration: 'PT15M'
    autoMitigate: false
  }
}

// ============================================================
// Outputs
// ============================================================

output dcrLinuxId string = dcrLinux.id
output dcrWindowsId string = dcrWindows.id
output actionGroupId string = actionGroup.id
