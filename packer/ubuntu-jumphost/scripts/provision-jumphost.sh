#!/bin/bash
# ============================================================
# Packer Provisioning Script — Ubuntu 22.04 Jumphost Image
# Installs XFCE Desktop, xRDP, Ansible, Azure CLI, DevOps tools
# NOTE: User passwords and SSH keys are set at deployment time
#       by Azure osProfile, NOT baked into the image.
# ============================================================

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========================================="
echo "Packer: Ubuntu 22.04 Jumphost Image Build"
echo "========================================="

# =============================================================================
# STEP 1: System Update
# =============================================================================

echo "[1/14] Updating system packages..."
apt update -qq
apt upgrade -y -qq

# =============================================================================
# STEP 2: Install Firewalld (replace UFW)
# =============================================================================

echo "[2/14] Removing UFW and installing firewalld..."
systemctl stop ufw || true
systemctl disable ufw || true
apt remove -y ufw
apt install -y firewalld

systemctl enable firewalld
systemctl start firewalld
sleep 2

firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3389/tcp
firewall-cmd --reload

# =============================================================================
# STEP 3: Install XFCE Desktop Environment
# =============================================================================

echo "[3/14] Installing XFCE Desktop Environment..."
apt install -y xfce4 xfce4-goodies

echo "[4/14] Installing X11 components..."
apt install -y xorg dbus-x11 x11-xserver-utils xterm

systemctl set-default graphical.target

# =============================================================================
# STEP 4: Install and Configure xRDP
# =============================================================================

echo "[5/14] Installing and configuring xRDP..."
apt install -y xrdp
systemctl enable xrdp

adduser xrdp ssl-cert || true

cat > /etc/xrdp/startwm.sh <<'XRDP_STARTWM'
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
XRDP_STARTWM
chmod +x /etc/xrdp/startwm.sh

# =============================================================================
# STEP 5: Install Remmina (RDP/VNC Client)
# =============================================================================

echo "[6/14] Installing Remmina..."
apt-add-repository -y ppa:remmina-ppa-team/remmina-next
apt update -qq
apt install -y remmina remmina-plugin-rdp remmina-plugin-secret

# =============================================================================
# STEP 6: Install Ansible and Configuration Management Tools
# =============================================================================

echo "[7/14] Installing Ansible and dependencies..."
apt install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt install -y ansible python3-pip python3-winrm python3-requests sshpass

# =============================================================================
# STEP 7: Install Azure CLI
# =============================================================================

echo "[8/14] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# =============================================================================
# STEP 8: Install Azure Ansible Collection + Python SDK
# =============================================================================

echo "[9/14] Installing Azure Ansible Collection and Python SDK..."
# Install globally so any user can use it
ansible-galaxy collection install azure.azcollection --force -p /usr/share/ansible/collections
pip3 install -r /usr/share/ansible/collections/ansible_collections/azure/azcollection/requirements.txt

# =============================================================================
# STEP 9: Install Visual Studio Code
# =============================================================================

echo "[10/14] Installing Visual Studio Code..."
rm -f /etc/apt/sources.list.d/vscode.list
rm -f /etc/apt/keyrings/packages.microsoft.gpg

wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
rm -f packages.microsoft.gpg
apt update -qq
apt install -y code

# =============================================================================
# STEP 10: Install Firefox ESR
# =============================================================================

echo "[11/14] Installing Firefox ESR..."
add-apt-repository -y ppa:mozillateam/ppa

cat > /etc/apt/preferences.d/mozilla-firefox <<'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

apt update -qq
apt install -y firefox-esr

update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox-esr 200
update-alternatives --set x-www-browser /usr/bin/firefox-esr

# =============================================================================
# STEP 11: Install DevOps Tools
# =============================================================================

echo "[12/14] Installing DevOps tools..."
apt install -y \
    git vim nano mc wget curl htop tmux screen \
    net-tools dnsutils tcpdump nmap telnet netcat \
    jq tree bash-completion unzip zip tar build-essential

# =============================================================================
# STEP 12: Configure SSH Hardening
# =============================================================================

echo "[13/14] Configuring SSH..."
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# =============================================================================
# STEP 13: Create MOTD
# =============================================================================

cat > /etc/motd <<'MOTD_EOF'
==========================================
SC MEDIA SRL - DevOps Jumphost
==========================================

OS: Ubuntu 22.04 LTS + XFCE Desktop
Image: Packer Golden Image
RDP Port: 3389

Installed Tools:
- Ansible, Azure CLI, Git, VS Code
- Firefox ESR, Remmina (RDP/VNC)
- DevOps utilities (htop, tmux, jq, etc.)

Quick Commands:
  ansible --version
  az --version
  az login

==========================================
MOTD_EOF

# =============================================================================
# STEP 14: Cleanup
# =============================================================================

echo "[14/14] Cleaning up..."
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "========================================="
echo "Packer jumphost provisioning complete!"
echo "========================================="
