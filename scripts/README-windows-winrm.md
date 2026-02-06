# Windows WinRM Bootstrap Instructions

## Overview
After deploying Windows Server VMs with Bicep, they need WinRM (Windows Remote Management) configured to allow Ansible connectivity from the jumphost.

**Target VMs:**
- vm-db-01 (Windows Server 2022 - SQL Server)
- vm-fs-01 (Windows Server 2022 - File Server)

**What WinRM Enables:**
- Remote PowerShell execution
- Ansible configuration management via `ansible_connection=winrm`
- Remote management from jumphost without RDP

## Prerequisites

- ✅ Infrastructure deployed via Bicep
- ✅ Windows VMs are running
- ✅ Azure CLI installed on your local machine
- ✅ Network connectivity to VMs (NSG rules allow management)

## Quick Bootstrap (Windows PowerShell)

Run this command from your **local machine** (not jumphost) to configure WinRM on Windows VMs:

### For vm-db-01 (Database Server)

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts '@scripts/bootstrap-windows-winrm.ps1'
```

### For vm-fs-01 (File Server)

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-fs-01 `
  --command-id RunPowerShellScript `
  --scripts '@scripts/bootstrap-windows-winrm.ps1'
```

## Quick Bootstrap (Linux/macOS Bash)

```bash
# Database Server
az vm run-command invoke \
  --resource-group rg-mediasrl-productie-swedencentral \
  --name vm-db-01 \
  --command-id RunPowerShellScript \
  --scripts @scripts/bootstrap-windows-winrm.ps1

# File Server
az vm run-command invoke \
  --resource-group rg-mediasrl-productie-swedencentral \
  --name vm-fs-01 \
  --command-id RunPowerShellScript \
  --scripts @scripts/bootstrap-windows-winrm.ps1
```

## What the Bootstrap Script Does

1. ✅ Enables PowerShell Remoting (`Enable-PSRemoting -Force`)
2. ✅ Configures WinRM service (Automatic startup)
3. ✅ Creates HTTP listener on port 5985
4. ✅ Configures authentication methods (Basic, Negotiate, Kerberos, CredSSP)
5. ✅ Allows unencrypted traffic (for HTTP - use HTTPS in production)
6. ✅ Configures Windows Firewall rules (opens port 5985)
7. ✅ Sets network profile to Private
8. ✅ Enables CredSSP for delegated authentication
9. ✅ Tests WinRM configuration locally
10. ✅ Logs all output to `C:\Temp\winrm-bootstrap-YYYYMMDD-HHMMSS.log`

## Expected Duration

- Script execution: ~2-3 minutes per VM
- No reboot required

## After Bootstrap

### Verify WinRM from Local Machine

```powershell
# Test WinRM connectivity (requires PSRemoting)
Enter-PSSession -ComputerName <vm-private-ip> -Credential azureadmin

# Or using Test-WSMan
Test-WSMan -ComputerName <vm-private-ip> -Port 5985
```

### Test from Jumphost (Ansible)

From jumphost via SSH:

```bash
# Test WinRM connectivity with Ansible
ansible windows -m win_ping

# If inventory is not configured yet, test manually:
ansible vm-db-01 -i "vm-db-01," -m win_ping \
  -e "ansible_connection=winrm" \
  -e "ansible_winrm_transport=ntlm" \
  -e "ansible_winrm_server_cert_validation=ignore" \
  -e "ansible_port=5985" \
  -e "ansible_user=azureadmin" \
  -e "ansible_password=Str0ng_P@ssw0rd_2026!"
```

## WinRM Configuration Details

### Ports Opened:
- **5985** (HTTP) - Unencrypted WinRM
- **5986** (HTTPS) - Encrypted WinRM (not configured by default)

### Authentication Methods Enabled:
- **Basic** - Username/password (use with caution, requires HTTPS in production)
- **Negotiate** - NTLM or Kerberos (automatic selection)
- **Kerberos** - Active Directory authentication
- **CredSSP** - Credential delegation (for multi-hop scenarios)

### Ansible Inventory Variables:

```ini
[database]
vm-db-01 ansible_host=10.10.10.7

[fileserver]
vm-fs-01 ansible_host=10.10.10.8

[windows:children]
database
fileserver

[windows:vars]
ansible_connection=winrm
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_port=5985
ansible_user=azureadmin
ansible_password=Str0ng_P@ssw0rd_2026!
```

## Security Notes

⚠️ **IMPORTANT:** This configuration uses **HTTP (port 5985)** for simplicity. For production environments:

1. **Use HTTPS (port 5986)** with valid SSL certificates
2. **Disable Basic authentication** over HTTP
3. **Use Kerberos or CredSSP** instead of NTLM
4. **Store passwords in Ansible Vault**, not plaintext inventory
5. **Restrict WinRM access** to jumphost IP only (NSG rules)

### Hardening WinRM (Post-Deployment)

```powershell
# Disable HTTP listener (use HTTPS only)
Remove-Item -Path WSMan:\localhost\Listener -Recurse -Force

# Create HTTPS listener with certificate
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbprint <thumbprint>

# Disable unencrypted traffic
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false

# Disable Basic authentication
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false
```

## Troubleshooting

### WinRM Not Responding

Check if WinRM service is running:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-Service WinRM"
```

### Firewall Blocking WinRM

Check firewall rules:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-NetFirewallRule -DisplayGroup 'Windows Remote Management'"
```

### Test WinRM Locally on VM

Via RDP (if needed for debugging):

```powershell
# Test WinRM locally
Test-WSMan -ComputerName localhost

# View WinRM configuration
winrm get winrm/config

# Check listeners
Get-ChildItem WSMan:\localhost\Listener
```

### Ansible Connection Fails

Common errors and solutions:

**Error:** `winrm or requests is not installed: No module named 'winrm'`
- **Solution:** Install python3-winrm on jumphost: `sudo apt install -y python3-winrm`

**Error:** `401 Unauthorized`
- **Solution:** Check username/password in inventory, verify Basic auth is enabled

**Error:** `Connection timeout`
- **Solution:** Check NSG rules allow jumphost → Windows VMs on port 5985

**Error:** `SSL certificate validation failed`
- **Solution:** Add `ansible_winrm_server_cert_validation=ignore` to inventory

## Manual Configuration (Alternative)

If `az vm run-command` doesn't work, use Azure Portal Serial Console or RDP:

1. Azure Portal → vm-db-01 → Serial Console (or RDP)
2. Login as `azureadmin`
3. Open PowerShell as Administrator
4. Copy/paste commands from `scripts/bootstrap-windows-winrm.ps1`

## Verification Checklist

- [ ] WinRM service is running on Windows VMs
- [ ] Port 5985 is open in Windows Firewall
- [ ] NSG allows jumphost → Windows VMs on port 5985
- [ ] `Test-WSMan -ComputerName localhost` succeeds on Windows VMs
- [ ] `ansible windows -m win_ping` succeeds from jumphost
- [ ] Bootstrap log exists in `C:\Temp\winrm-bootstrap-*.log`

## Next Steps After WinRM Bootstrap

1. Configure Ansible inventory with Windows VMs
2. Test connectivity: `ansible windows -m win_ping`
3. Run Ansible playbooks to configure SQL Server and File Server
4. Harden WinRM configuration (HTTPS, disable Basic auth)

## Bootstrap Log File

All bootstrap output is saved to `C:\Temp\winrm-bootstrap-YYYYMMDD-HHMMSS.log` on the Windows VM for troubleshooting.

To view the log:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-Content C:\Temp\winrm-bootstrap-*.log -Tail 50"
```
