# ============================================================
# Script 0b: Bootstrap Pipeline RBAC — SC MEDIA SRL
#
# Run ONCE (as a user who can create custom role definitions,
# e.g. an Owner assignment — even one restricted by an ABAC
# "constrained delegation" condition works, since that condition
# only restricts roleAssignments/write for Owner, User Access
# Administrator and Role Based Access Control Administrator —
# it does NOT restrict roleDefinitions/write).
#
# Problem this solves:
#   The CI/CD pipeline's Service Principal needs to create Azure
#   role assignments (bicep/modules/role-assignment.bicep grants
#   roles to VM managed identities). Built-in roles that include
#   Microsoft.Authorization/roleAssignments/write are only Owner,
#   User Access Administrator, and Role Based Access Control
#   Administrator — all three blocked by the ABAC condition on
#   this subscription. A custom role (different GUID, same single
#   permission, nothing else) sidesteps the condition entirely.
#
# Usage:
#   az login
#   .\scripts\0b-bootstrap-pipeline-rbac.ps1
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\Write-Log.ps1"
$_LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
Start-LogSession -ScriptTitle "Bootstrap Pipeline RBAC" -LogDirectory $_LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

# ============================================================
# Configuration
# ============================================================

$SubscriptionId  = '7a0255bf-d664-4920-afb0-c523b49c1908'
$ResourceGroup   = 'rg-mediasrl-productie-swedencentral'
$PipelineSpObjId = '8f4a4212-79ea-42a1-a60a-f5e3fa3d9bcf'   # azure-service-connection Service Principal
$CustomRoleName  = 'MediaSRL Pipeline Role Assignment Writer'

$Scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

# ============================================================
# STEP 1: Create the custom role definition (idempotent)
# ============================================================

Write-Log-Header "Rol custom pentru pipeline" -Step 1 -Total 2

$existing = az role definition list --name $CustomRoleName --query "[0].roleName" -o tsv 2>$null
if ($existing) {
    Write-Log-OK "Rolul custom exista deja" -Detail $CustomRoleName
} else {
    Write-Log-Step "Creare rol custom: $CustomRoleName"

    $roleDef = @{
        Name             = $CustomRoleName
        IsCustom         = $true
        Description      = 'Allows creating/deleting Azure role assignments for automated deployment pipelines (bicep/modules/role-assignment.bicep). Deliberately excludes all other privileges.'
        Actions          = @(
            'Microsoft.Authorization/roleAssignments/write'
            'Microsoft.Authorization/roleAssignments/delete'
            'Microsoft.Authorization/roleAssignments/read'
        )
        NotActions       = @()
        AssignableScopes = @($Scope)
    }

    $tmpFile = New-TemporaryFile
    ($roleDef | ConvertTo-Json -Depth 5) | Set-Content -Path $tmpFile -Encoding utf8

    az role definition create --role-definition $tmpFile.FullName | Out-Null
    Remove-Item $tmpFile -Force

    Write-Log-OK "Rol custom creat" -Detail $CustomRoleName
}

# ============================================================
# STEP 2: Assign the custom role to the pipeline Service Principal
# ============================================================

Write-Log-Header "Atribuire rol catre Service Principal" -Step 2 -Total 2

$already = az role assignment list --assignee-object-id $PipelineSpObjId --role $CustomRoleName --scope $Scope --query "[0].id" -o tsv 2>$null
if ($already) {
    Write-Log-OK "Service Principal are deja rolul atribuit" -Detail $Scope
} else {
    az role assignment create `
        --assignee-object-id $PipelineSpObjId `
        --assignee-principal-type ServicePrincipal `
        --role $CustomRoleName `
        --scope $Scope | Out-Null
    Write-Log-OK "Rol atribuit Service Principal-ului pipeline" -Detail "$CustomRoleName @ $Scope"
}

Write-Log-Info "Propagarea RBAC poate dura pana la 10 minute inainte ca pipeline-ul sa poata folosi permisiunea."

Stop-LogSession
