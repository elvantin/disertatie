// ============================================================
// Module: VM Custom Script Extension
// Runs a bootstrap script on a Linux VM
// ============================================================

@description('VM name to attach the extension to')
param vmName string

@description('Azure region')
param location string

@description('Inline script to execute')
param scriptContent string

@description('Extension name')
param extensionName string = 'CustomScriptExtension'

@description('Tags to apply to resources')
param tags object = {}

// ----- Custom Script Extension for Linux -----

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' existing = {
  name: vmName
}

resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: extensionName
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      script: base64(scriptContent)
    }
  }
}

output extensionName string = customScriptExtension.name
output extensionStatus string = customScriptExtension.properties.provisioningState
