#!/bin/bash
# ============================================================
# Bootstrap Script for Jumphost (Ubuntu 22.04 LTS)
# Installs xRDP + XFCE Desktop + Ansible + DevOps Tools
# ============================================================

set -e

# Setup logging - save all output to /tmp
LOGFILE="/tmp/jumphost-bootstrap-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "========================================="
echo "SC MEDIA SRL - Jumphost Bootstrap"
echo "Ubuntu 22.04 LTS Configuration"
echo "Logging to: $LOGFILE"
echo "========================================="

# Admin user configuration
ADMIN_USER="azureadmin"
ADMIN_PASSWORD="Str0ng_P@ssw0rd_2026!"

# =============================================================================
# STEP 1: System Update
# =============================================================================

echo ""
echo "[1/23] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# =============================================================================
# STEP 2: User Authentication Configuration
# =============================================================================

echo "[2/23] Setting password for ${ADMIN_USER}..."
echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | chpasswd
passwd -u "${ADMIN_USER}"

echo "[3/23] Enabling password authentication in SSH..."
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart ssh

# =============================================================================
# STEP 3: Replace UFW with Firewalld
# =============================================================================

echo "[4/23] Removing UFW and installing firewalld..."
systemctl stop ufw || true
systemctl disable ufw || true
apt-get remove -y ufw
apt-get install -y firewalld

echo "[5/23] Configuring firewalld..."
systemctl enable firewalld
systemctl start firewalld
sleep 2

echo "[6/23] Opening firewall ports (SSH 22 + RDP 3389)..."
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=3389/tcp
firewall-cmd --reload

# =============================================================================
# STEP 4: Install XFCE Desktop Environment
# =============================================================================

echo "[7/23] Installing XFCE Desktop Environment..."
apt-get install -y xfce4 xfce4-goodies

echo "[8/23] Installing additional X11 components..."
apt-get install -y \
    xorg \
    dbus-x11 \
    x11-xserver-utils \
    xterm

echo "[9/23] Setting graphical target as default..."
systemctl set-default graphical.target

# =============================================================================
# STEP 5: Install and Configure xRDP
# =============================================================================

echo "[10/23] Installing xRDP..."
apt-get install -y xrdp

echo "[11/23] Configuring xRDP for XFCE..."
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

echo "[12/23] Creating .xsession for ${ADMIN_USER}..."
echo "xfce4-session" | tee /home/${ADMIN_USER}/.xsession
chmod +x /home/${ADMIN_USER}/.xsession
chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.xsession

echo "[13/23] Restarting xRDP service..."
systemctl restart xrdp

# =============================================================================
# STEP 6: Install Remote Desktop Clients (Remmina)
# =============================================================================

echo "[14/23] Installing Remmina (RDP/VNC client) from PPA..."
apt-add-repository -y ppa:remmina-ppa-team/remmina-next
apt-get update
apt-get install -y remmina remmina-plugin-rdp remmina-plugin-secret

# =============================================================================
# STEP 7: Install Ansible and Configuration Management Tools
# =============================================================================

echo "[15/23] Installing Ansible and dependencies..."
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

echo "[16/24] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# =============================================================================
# STEP 8b: Install Azure Ansible Collection + Python SDK
# =============================================================================

echo "[17/24] Installing Azure Ansible Collection and Python SDK..."
# Install the Azure collection for Ansible (needed for azure_rm dynamic inventory)
# Use -p to install into ~/ansible/collections/ instead of default ~/.ansible/collections/
ansible-galaxy collection install azure.azcollection --force -p /root/ansible/collections

# Install Python dependencies required by the azure_rm inventory plugin
pip3 install -r /root/ansible/collections/ansible_collections/azure/azcollection/requirements.txt

# Also install for the admin user
su - ${ADMIN_USER} -c "ansible-galaxy collection install azure.azcollection --force -p /home/${ADMIN_USER}/ansible/collections"
pip3 install -r /home/${ADMIN_USER}/ansible/collections/ansible_collections/azure/azcollection/requirements.txt

# =============================================================================
# STEP 9: Install Visual Studio Code
# =============================================================================

echo "[18/24] Installing Visual Studio Code..."
# Clean up any existing VS Code repository configuration to avoid conflicts
rm -f /etc/apt/sources.list.d/vscode.list
rm -f /etc/apt/keyrings/packages.microsoft.gpg

# Install VS Code using Microsoft's repository
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
install -D -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/packages.microsoft.gpg
sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg
apt-get update -qq
apt-get install -y code

# =============================================================================
# STEP 10: Install Firefox ESR Browser
# =============================================================================

echo "[18/23] Installing Firefox ESR from Mozilla Team PPA..."
# Add Mozilla Team PPA for Firefox ESR (Snap version doesn't work well with xRDP)
add-apt-repository -y ppa:mozillateam/ppa

# Set apt preferences to prioritize Mozilla Team PPA over Snap
cat > /etc/apt/preferences.d/mozilla-firefox <<'EOF'
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
EOF

# Update and install Firefox ESR
apt-get update -qq
apt-get install -y firefox-esr

# Set Firefox ESR as default browser for all users
update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/firefox-esr 200
update-alternatives --set x-www-browser /usr/bin/firefox-esr

# Set as default browser for the admin user
mkdir -p /home/${ADMIN_USER}/.config
cat > /home/${ADMIN_USER}/.config/mimeapps.list <<'MIMEAPPS'
[Default Applications]
text/html=firefox-esr.desktop
x-scheme-handler/http=firefox-esr.desktop
x-scheme-handler/https=firefox-esr.desktop
x-scheme-handler/about=firefox-esr.desktop
x-scheme-handler/unknown=firefox-esr.desktop
MIMEAPPS

chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.config

# =============================================================================
# STEP 11: Install DevOps Tools
# =============================================================================

echo "[19/23] Installing DevOps tools..."
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
# STEP 12: Create Workspace Directories
# =============================================================================

echo "[20/23] Creating workspace directories..."
mkdir -p /home/${ADMIN_USER}/ansible-workspace
mkdir -p /home/${ADMIN_USER}/Desktop
mkdir -p /home/${ADMIN_USER}/.local/share/remmina
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/ansible-workspace
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/Desktop
chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.local

# Create pre-configured Remmina profiles for Windows VMs
echo "[20/23] Creating Remmina RDP profiles for Windows VMs..."

# Remmina profile for vm-db-01
cat > /home/${ADMIN_USER}/.local/share/remmina/vm-db-01.remmina <<'REMMINA_DB'
[remmina]
password=U3RyMG5nX1BAc3N3MHJkXzIwMjYh
gateway_username=
notes_text=
vc=
preferipv6=0
ssh_tunnel_certfile=
resolution_mode=1
gateway_server=
ssh_tunnel_enabled=0
ssh_tunnel_password=
serialname=
printer_overrides=
name=Windows DB Server (vm-db-01)
console=0
colordepth=32
security=negotiate
precommand=
disable_fastpath=0
postcommand=
left-handed=0
gateway_domain=
server=vm-db-01
ssh_tunnel_username=
glyph-cache=0
ssh_tunnel_privatekey=
audiosignal=
resolution_width=0
disableclipboard=0
ssh_tunnel_passphrase=
cert_ignore=1
gateway_password=
window_maximize=0
sound=off
resolution_height=0
network=lan
keymap=
ssh_tunnel_auth=0
username=azureadmin
gateway_usage=0
ignore-tls-errors=1
group=
domain=
disableserverinput=0
protocol=RDP
ssh_tunnel_loopback=0
showcursor=0
multimon=0
ssh_tunnel_server=
serialdriver=
useproxyenv=0
disableautoreconnect=0
clientname=
shareparallel=0
quality=2
relax-order-checks=0
old-license=0
serialpermissive=0
span=0
disablepasswordstoring=0
sharefolder=
viewmode=1
smartcardname=
shareprinter=0
parallelpath=
drive=
shareserial=0
base-cred-for-gw=0
gateway_privatekey=
smartsharingmode=0
usb=
ssh_tunnel_certfile=
exec=
enable-autostart=0
serialpath=
loadbalanceinfo=
disableencryption=0
microphone=
gateway_publickey=
REMMINA_DB

# Remmina profile for vm-fs-01
cat > /home/${ADMIN_USER}/.local/share/remmina/vm-fs-01.remmina <<'REMMINA_FS'
[remmina]
password=U3RyMG5nX1BAc3N3MHJkXzIwMjYh
gateway_username=
notes_text=
vc=
preferipv6=0
ssh_tunnel_certfile=
resolution_mode=1
gateway_server=
ssh_tunnel_enabled=0
ssh_tunnel_password=
serialname=
printer_overrides=
name=Windows File Server (vm-fs-01)
console=0
colordepth=32
security=negotiate
precommand=
disable_fastpath=0
postcommand=
left-handed=0
gateway_domain=
server=vm-fs-01
ssh_tunnel_username=
glyph-cache=0
ssh_tunnel_privatekey=
audiosignal=
resolution_width=0
disableclipboard=0
ssh_tunnel_passphrase=
cert_ignore=1
gateway_password=
window_maximize=0
sound=off
resolution_height=0
network=lan
keymap=
ssh_tunnel_auth=0
username=azureadmin
gateway_usage=0
ignore-tls-errors=1
group=
domain=
disableserverinput=0
protocol=RDP
ssh_tunnel_loopback=0
showcursor=0
multimon=0
ssh_tunnel_server=
serialdriver=
useproxyenv=0
disableautoreconnect=0
clientname=
shareparallel=0
quality=2
relax-order-checks=0
old-license=0
serialpermissive=0
span=0
disablepasswordstoring=0
sharefolder=
viewmode=1
smartcardname=
shareprinter=0
parallelpath=
drive=
shareserial=0
base-cred-for-gw=0
gateway_privatekey=
smartsharingmode=0
usb=
ssh_tunnel_certfile=
exec=
enable-autostart=0
serialpath=
loadbalanceinfo=
disableencryption=0
microphone=
gateway_publickey=
REMMINA_FS

chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.local/share/remmina
chmod 600 /home/${ADMIN_USER}/.local/share/remmina/*.remmina

# =============================================================================
# STEP 13: Create Welcome Message
# =============================================================================

echo "[21/23] Creating welcome message..."
cat > /etc/motd <<'MOTD_EOF'
==========================================
SC MEDIA SRL - DevOps Jumphost
==========================================

Environment: Production
OS: Ubuntu 22.04 LTS + XFCE Desktop
RDP Port: 3389

Installed Tools:
- Ansible & Azure CLI
- Git, VS Code, Firefox
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

RDP to Windows VMs (using Remmina GUI):
  1. Open Remmina from Applications menu
  2. Create new RDP connection:
     - Server: vm-db-01 (or vm-fs-01)
     - Username: azureadmin
     - Password: Str0ng_P@ssw0rd_2026!
     - Color depth: RemoteFX (32 bpp)
     - Security: Negotiate
     - Ignore certificate: YES
     - Disable NLA: NO (leave NLA enabled)
  3. Save and connect

Workspace: ~/ansible-workspace
==========================================
MOTD_EOF

# =============================================================================
# STEP 14: Verify Services
# =============================================================================

echo "[22/23] Verifying services..."
systemctl is-active firewalld || (echo "ERROR: firewalld is not running" && exit 1)
systemctl is-active xrdp || (echo "ERROR: xrdp is not running" && exit 1)
systemctl is-active ssh || (echo "ERROR: ssh is not running" && exit 1)

# =============================================================================
# STEP 15: Cleanup
# =============================================================================

echo "[23/23] Cleaning up..."
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
echo "  - Browser: Firefox"
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
echo "Remmina RDP Profiles:"
echo "  Pre-configured profiles created for:"
echo "  - vm-db-01 (Windows DB Server)"
echo "  - vm-fs-01 (Windows File Server)"
echo "  Open Remmina and select the saved connection!"
echo ""
echo "Bootstrap Log File: ${LOGFILE}"
echo "  (saved for troubleshooting and verification)"
echo ""
echo "IMPORTANT: Change the default password after first login!"
echo ""
echo "========================================="

# Reboot conditionally: skip if running non-interactively (e.g., Azure Custom Script Extension)
# When run via CSE, stdin is not a terminal, so [ -t 0 ] is false
if [ -t 0 ]; then
    echo "System will reboot in 10 seconds..."
    sleep 10
    reboot
else
    echo "Skipping automatic reboot (running via Azure Custom Script Extension)"
    echo "The VM will apply changes on next reboot or you can reboot manually: sudo reboot"
fi
