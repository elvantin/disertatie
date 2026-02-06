#!/bin/bash
# ============================================================
# Bootstrap Script for Jumphost (Ubuntu 22.04 LTS)
# Installs xRDP + XFCE Desktop + Ansible + DevOps Tools
# ============================================================

set -e

echo "========================================="
echo "SC MEDIA SRL - Jumphost Bootstrap"
echo "Ubuntu 22.04 LTS Configuration"
echo "========================================="

# Admin user configuration
ADMIN_USER="azureadmin"
ADMIN_PASSWORD="Str0ng_P@ssw0rd_2026!"

# =============================================================================
# STEP 1: System Update
# =============================================================================

echo ""
echo "[1/22] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# =============================================================================
# STEP 2: User Authentication Configuration
# =============================================================================

echo "[2/22] Setting password for ${ADMIN_USER}..."
echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | chpasswd
passwd -u "${ADMIN_USER}"

echo "[3/22] Enabling password authentication in SSH..."
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# =============================================================================
# STEP 3: Replace UFW with Firewalld
# =============================================================================

echo "[4/22] Removing UFW and installing firewalld..."
systemctl stop ufw || true
systemctl disable ufw || true
apt-get remove -y ufw
apt-get install -y firewalld

echo "[5/22] Configuring firewalld..."
systemctl enable firewalld
systemctl start firewalld
sleep 2

echo "[6/22] Opening firewall ports (SSH 22 + RDP 3389)..."
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3389/tcp
firewall-cmd --permanent --add-service=RDP
firewall-cmd --reload

# =============================================================================
# STEP 4: Install XFCE Desktop Environment
# =============================================================================

echo "[7/22] Installing XFCE Desktop Environment..."
apt-get install -y xfce4 xfce4-goodies

echo "[8/22] Installing additional X11 components..."
apt-get install -y \
    xorg \
    dbus-x11 \
    x11-xserver-utils \
    xterm

echo "[9/22] Setting graphical target as default..."
systemctl set-default graphical.target

# =============================================================================
# STEP 5: Install and Configure xRDP
# =============================================================================

echo "[10/22] Installing xRDP..."
apt-get install -y xrdp

echo "[11/22] Configuring xRDP for XFCE..."
systemctl enable xrdp
systemctl start xrdp

# Add xrdp user to ssl-cert group
adduser xrdp ssl-cert

# Configure xRDP to use XFCE session
cat > /etc/xrdp/startwm.sh <<'XRDP_STARTWM'
#!/bin/sh
# xRDP X session start script for XFCE

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# Unset session manager variables
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Start XFCE4 session
exec startxfce4
XRDP_STARTWM
chmod +x /etc/xrdp/startwm.sh

echo "[12/22] Creating .xsession for ${ADMIN_USER}..."
echo "xfce4-session" | tee /home/${ADMIN_USER}/.xsession
chmod +x /home/${ADMIN_USER}/.xsession
chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.xsession

echo "[13/22] Restarting xRDP service..."
systemctl restart xrdp

# =============================================================================
# STEP 6: Install Remote Desktop Clients (Remmina)
# =============================================================================

echo "[14/22] Installing Remmina (RDP/VNC client)..."
apt-get install -y remmina remmina-plugin-vnc remmina-plugin-rdp

# =============================================================================
# STEP 7: Install Ansible and Configuration Management Tools
# =============================================================================

echo "[15/22] Installing Ansible and dependencies..."
apt-get install -y \
    software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y \
    ansible \
    python3-pip \
    python3-winrm \
    python3-requests \
    sshpass

# =============================================================================
# STEP 8: Install Azure CLI
# =============================================================================

echo "[16/22] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# =============================================================================
# STEP 9: Install Visual Studio Code
# =============================================================================

echo "[17/22] Installing Visual Studio Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg
apt-get update -qq
apt-get install -y code

# =============================================================================
# STEP 10: Install DevOps Tools
# =============================================================================

echo "[18/22] Installing DevOps tools..."
apt-get install -y \
    git \
    vim \
    nano \
    mc \
    wget \
    curl \
    htop \
    tmux \
    screen \
    net-tools \
    dnsutils \
    tcpdump \
    nmap \
    telnet \
    netcat \
    jq \
    tree \
    bash-completion \
    unzip \
    zip \
    tar \
    build-essential

# =============================================================================
# STEP 11: Create Workspace Directories
# =============================================================================

echo "[19/22] Creating workspace directories..."
mkdir -p /home/${ADMIN_USER}/ansible-workspace
mkdir -p /home/${ADMIN_USER}/Desktop
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/ansible-workspace
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/Desktop

# =============================================================================
# STEP 12: Create Welcome Message
# =============================================================================

echo "[20/22] Creating welcome message..."
cat > /etc/motd <<'MOTD_EOF'
==========================================
SC MEDIA SRL - DevOps Jumphost
==========================================

Environment: Production
OS: Ubuntu 22.04 LTS + XFCE Desktop
RDP Port: 3389

Installed Tools:
- Ansible & Azure CLI
- Git, VS Code
- Remmina (RDP/VNC client for remote access)
- DevOps utilities (htop, tmux, jq, etc.)

Quick Commands:
  ansible --version
  az --version
  git --version

SSH to Linux VMs:
  ssh azureadmin@vm-web-01
  ssh azureadmin@vm-app-01
  ssh azureadmin@vm-cms-01

RDP to Windows VMs (using Remmina):
  remmina -c rdp://azureadmin@vm-fs-01
  remmina -c rdp://azureadmin@vm-db-01

Workspace: ~/ansible-workspace
==========================================
MOTD_EOF

# =============================================================================
# STEP 13: Verify Services
# =============================================================================

echo "[21/22] Verifying services..."
systemctl is-active firewalld || (echo "ERROR: firewalld is not running" && exit 1)
systemctl is-active xrdp || (echo "ERROR: xrdp is not running" && exit 1)
systemctl is-active ssh || (echo "ERROR: ssh is not running" && exit 1)

# =============================================================================
# STEP 14: Cleanup
# =============================================================================

echo "[22/22] Cleaning up..."
apt-get autoremove -y
apt-get clean

# =============================================================================
# COMPLETION
# =============================================================================

echo ""
echo "========================================="
echo "Bootstrap complete!"
echo "========================================="
echo ""
echo "Jumphost Configuration Summary:"
echo "  - OS: Ubuntu 22.04 LTS"
echo "  - Desktop: XFCE"
echo "  - xRDP: Running on port 3389"
echo "  - Firewall: firewalld (ports 22, 3389 open)"
echo "  - Ansible: $(ansible --version | head -1)"
echo "  - Azure CLI: $(az --version | head -1)"
echo "  - Remmina: $(remmina --version | head -1)"
echo ""
echo "RDP Connection Details:"
echo "  Address: <jumphost-public-ip>:3389"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASSWORD}"
echo ""
echo "IMPORTANT: Change the default password after first login!"
echo ""
echo "System will reboot in 10 seconds..."
echo "========================================="

sleep 10
reboot
