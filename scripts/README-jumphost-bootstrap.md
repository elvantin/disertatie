# Jumphost Bootstrap Instructions

## Overview
After deploying the infrastructure with Bicep, the jumphost (vm-jmp-01) needs to be configured with xRDP and XFCE desktop environment using the bootstrap script.

**VM Specifications:**
- Size: Standard_D2s_v3 (2 vCPU, 8GB RAM)
- OS: Ubuntu 22.04 LTS (Canonical)
- Disk: 64GB Standard SSD
- Desktop: XFCE (lightweight, optimized for RDP)
- Firewall: firewalld (replaces UFW)
- Tools: Ansible, Azure CLI, VS Code, Remmina, DevOps utilities

This manual bootstrap step is required because VM extensions trigger Azure Policy tag requirements that complicate deployment.

## Quick Bootstrap (Windows PowerShell)

Run this command after the Bicep deployment completes:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-jmp-01 `
  --command-id RunShellScript `
  --scripts @"
$(Get-Content -Path 'scripts\bootstrap-jumphost.sh' -Raw)
"@
```

**OR** if the above fails, use the file directly:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-jmp-01 `
  --command-id RunShellScript `
  --scripts '@scripts/bootstrap-jumphost.sh'
```

## Quick Bootstrap (Linux/macOS Bash)

```bash
az vm run-command invoke \
  --resource-group rg-mediasrl-productie-swedencentral \
  --name vm-jmp-01 \
  --command-id RunShellScript \
  --scripts @scripts/bootstrap-jumphost.sh
```

## What the Bootstrap Script Does

1. ✅ Sets password for `azureadmin` user
2. ✅ Enables password authentication in SSH
3. ✅ Installs EPEL repository
4. ✅ Installs firewalld
5. ✅ Installs xRDP and xRDP SELinux module
6. ✅ Configures firewall for RDP (port 3389) and SSH
7. ✅ Configures SELinux for xRDP
8. ✅ Installs XFCE Desktop Environment
9. ✅ Installs X Window System
10. ✅ Configures xRDP to use XFCE
11. ✅ Creates user desktop session configuration
12. ✅ Installs DevOps tools (git, vim, curl, htop, etc.)
13. ✅ Reboots the system

## Expected Duration

- Script execution: ~5-10 minutes
- Reboot: ~2-3 minutes
- **Total**: ~10-15 minutes

## After Bootstrap

Connect via RDP:
- **Address**: `<jumphost-public-ip>:3389`
- **Username**: `azureadmin`
- **Password**: `Str0ng_P@ssw0rd_2026!`

## Verification

Check if jumphost is ready for RDP:

```powershell
# Test RDP port (should return True)
Test-NetConnection -ComputerName <jumphost-public-ip> -Port 3389

# Check xRDP service status
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-jmp-01 `
  --command-id RunShellScript `
  --scripts "systemctl status xrdp"
```

## Troubleshooting

### RDP Connection Fails

1. Check NSG rules allow your IP on port 3389
2. Verify xRDP is running: `systemctl status xrdp`
3. Check firewall: `firewall-cmd --list-all`
4. Verify desktop is installed: `dnf grouplist | grep -i xfce`

### Connection Closes After Login

This usually means desktop environment is not properly installed:

```bash
# Reinstall XFCE
dnf groupinstall -y "Xfce" "base-x"

# Reconfigure xRDP
cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
chmod +x /etc/xrdp/startwm.sh

# Restart xRDP
systemctl restart xrdp
```

## Manual Configuration (Alternative)

If `az vm run-command` doesn't work, use Azure Portal Serial Console:

1. Azure Portal → vm-jmp-01 → Serial Console
2. Login with `azureadmin` (password not required for serial console)
3. Become root: `sudo su -`
4. Copy/paste commands from `scripts/bootstrap-jumphost.sh` one by one

## Security Notes

- Default password is `Str0ng_P@ssw0rd_2026!` - **change this immediately** after first login
- Password authentication is enabled for SSH - consider disabling after SSH key setup
- Firewall is configured to allow only RDP (3389) and SSH (22)
- SELinux is in enforcing mode with xRDP exceptions

## Next Steps After Bootstrap

1. Connect via RDP to jumphost
2. Change default password
3. Configure SSH keys for Linux VMs
4. Run Ansible playbooks from jumphost to configure other VMs
