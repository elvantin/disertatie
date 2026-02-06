# Jumphost Bootstrap Instructions

## Overview
After deploying the infrastructure with Bicep, the jumphost (vm-jmp-01) needs to be configured with xRDP and XFCE desktop environment using the bootstrap script.

**VM Specifications:**
- Size: Standard_D2s_v3 (2 vCPU, 8GB RAM)
- OS: Ubuntu 22.04 LTS (Canonical)
- Disk: 64GB Standard SSD
- Desktop: XFCE (lightweight, optimized for RDP)
- Browser: Firefox ESR (from Mozilla Team PPA)
- Firewall: firewalld (replaces UFW)
- Tools: Ansible, Azure CLI, VS Code, Remmina (with pre-configured profiles), DevOps utilities

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

1. ✅ Updates system packages (apt)
2. ✅ Sets password for `azureadmin` user
3. ✅ Enables password authentication in SSH
4. ✅ Removes UFW and installs firewalld
5. ✅ Configures firewalld (ports 22, 3389)
6. ✅ Installs XFCE Desktop Environment
7. ✅ Installs X11 components
8. ✅ Sets graphical target as default
9. ✅ Installs and configures xRDP for XFCE
10. ✅ Installs Remmina (RDP/VNC client)
11. ✅ Installs Ansible + dependencies (python3-winrm, sshpass)
12. ✅ Installs Azure CLI
13. ✅ Installs VS Code (from Microsoft repository)
14. ✅ Installs Firefox ESR (from Mozilla Team PPA)
15. ✅ Installs DevOps tools (git, vim, htop, tmux, jq, etc.)
16. ✅ Creates workspace directories
17. ✅ Creates pre-configured Remmina RDP profiles for Windows VMs
18. ✅ Creates MOTD (Message of the Day)
19. ✅ Verifies services (firewalld, xrdp, ssh)
20. ✅ Cleanup and reboot

## Expected Duration

- Script execution: ~8-12 minutes
- Reboot: ~2-3 minutes
- **Total**: ~12-15 minutes

## After Bootstrap

Connect via RDP:
- **Address**: `<jumphost-public-ip>:3389`
- **Username**: `azureadmin`
- **Password**: `Str0ng_P@ssw0rd_2026!`

## Pre-configured Remmina Profiles

The bootstrap script automatically creates Remmina RDP profiles for Windows VMs:
- **vm-db-01** (Windows DB Server)
- **vm-fs-01** (Windows File Server)

Simply open Remmina from the Applications menu and select the saved connection!

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
4. Verify desktop is installed: `dpkg -l | grep xfce4`

### Connection Closes After Login

This usually means desktop environment is not properly installed:

```bash
# Reinstall XFCE
sudo apt install -y xfce4 xfce4-goodies xorg

# Reconfigure xRDP
cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# Restart xRDP
sudo systemctl restart xrdp
```

### Firefox Not Working

If Firefox doesn't launch, install Firefox ESR from Mozilla Team PPA:

```bash
sudo add-apt-repository -y ppa:mozillateam/ppa
echo 'Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001' | sudo tee /etc/apt/preferences.d/mozilla-firefox
sudo apt update
sudo apt install -y firefox-esr
```

### Remmina Connection to Windows Crashes

If Remmina closes immediately when connecting to Windows Server:

1. Open Remmina
2. Edit the saved connection (vm-db-01)
3. Advanced tab → Security: Change to **"NLA protocol security"**
4. Advanced tab → Ignore certificate: **YES**
5. Save and reconnect

## Manual Configuration (Alternative)

If `az vm run-command` doesn't work, use Azure Portal Serial Console:

1. Azure Portal → vm-jmp-01 → Serial Console
2. Login with `azureadmin` and the password
3. Become root: `sudo su -`
4. Copy/paste commands from `scripts/bootstrap-jumphost.sh` one by one

## Security Notes

- Default password is `Str0ng_P@ssw0rd_2026!` - **change this immediately** after first login
- Password authentication is enabled for SSH and RDP
- SSH keys will be configured via Ansible after bootstrap
- Firewall is configured to allow only RDP (3389) and SSH (22)
- Ubuntu AppArmor is active (no SELinux on Ubuntu)

## Next Steps After Bootstrap

1. Connect via RDP to jumphost
2. Change default password: `passwd`
3. Test Firefox ESR browser
4. Test Remmina connection to vm-db-01
5. Configure SSH keys for Linux VMs (via Ansible)
6. Run Ansible playbooks from jumphost to configure other VMs

## Bootstrap Log File

All bootstrap output is saved to `/tmp/jumphost-bootstrap-YYYYMMDD-HHMMSS.log` for troubleshooting.
