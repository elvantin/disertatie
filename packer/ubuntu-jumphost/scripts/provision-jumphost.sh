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
# STEP 0: Fix sources.list
# =============================================================================
# Imaginile recente canonical/ubuntu-22_04-lts/server/latest pe Azure migrează
# spre formatul DEB822 (.sources), lăsând uneori linii malformate în
# /etc/apt/sources.list. Reconstruim sources.list curat înainte de apt update.

echo "[0/13] Rebuilding /etc/apt/sources.list (fix Azure image DEB822 migration)..."
cat > /etc/apt/sources.list << 'SOURCES'
deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
SOURCES

for f in /etc/apt/sources.list.d/ubuntu.sources \
         /etc/apt/sources.list.d/canonical*.list \
         /etc/apt/sources.list.d/ubuntu-esm*.list; do
  [ -f "$f" ] && rm -f "$f" && echo "  Removed conflicting: $f"
done

# =============================================================================
# STEP 1: System Update
# =============================================================================

echo "[1/13] Updating system packages..."
apt update -qq
apt upgrade -y -qq

# =============================================================================
# STEP 2: Install Firewalld (replace UFW)
# =============================================================================

echo "[2/13] Removing UFW and installing firewalld..."
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

echo "[3/13] Installing XFCE Desktop Environment..."
apt install -y xfce4 xfce4-goodies

echo "[4/13] Installing X11 components..."
apt install -y xorg dbus-x11 x11-xserver-utils xterm

systemctl set-default graphical.target

# =============================================================================
# STEP 4: Install and Configure xRDP
# =============================================================================

echo "[5/13] Installing and configuring xRDP..."
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

echo "[6/13] Installing Remmina..."
apt-add-repository -y ppa:remmina-ppa-team/remmina-next
apt update -qq
apt install -y remmina remmina-plugin-rdp remmina-plugin-secret

# =============================================================================
# STEP 6: Install Ansible and Configuration Management Tools
# =============================================================================

echo "[7/13] Installing Ansible and dependencies..."
apt install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt install -y ansible python3-pip python3-winrm python3-requests sshpass

# =============================================================================
# STEP 7: Install Azure CLI
# =============================================================================

echo "[8/13] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# =============================================================================
# STEP 8: Install Visual Studio Code
# =============================================================================
# NOTE: azure.azcollection (Ansible modules pentru Azure resources) NU este
# instalat intentionat — nu folosim Ansible pentru a gestiona resurse Azure
# (AKS, CosmosDB, IoT Hub etc.). Resursele Azure sunt gestionate prin Azure CLI.
# Ansible e folosit doar pentru configurarea interna a VM-urilor (SSH/WinRM).
# Daca e necesar in viitor: ansible-galaxy collection install azure.azcollection

echo "[9/13] Installing Visual Studio Code..."
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

echo "[10/13] Installing Firefox ESR..."
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

echo "[11/13] Installing DevOps tools..."
apt install -y \
    git vim nano mc wget curl htop tmux screen \
    net-tools dnsutils tcpdump nmap telnet netcat \
    jq tree bash-completion unzip zip tar build-essential

# =============================================================================
# STEP 12: Configurare SSH hardening
# =============================================================================
# PROBLEMA: cloud-init creeaza /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
# la primul boot cu PasswordAuthentication no (cand detecteaza cheie SSH in osProfile).
# Pe Ubuntu 22.04, walinuxagent depinde de cloud-init — nu putem elimina cloud-init.
#
# SOLUTIE: Folosim prefixul "10-" pentru fisierul nostru.
# sshd_config.d se citeste ALFABETIC, prima aparitie castiga.
# "10-mediasrl.conf" se citeste INAINTE de "60-cloudimg-settings.conf" → castigam.
#
# Strat suplimentar: cloud-init override (ssh_pwauth: true) ii spune cloud-init
# sa scrie PasswordAuthentication yes in 60-cloudimg-settings.conf.
# Accesul SSH ramane sigur prin NSG (portul 22 whitelist pe IP-ul admin).

echo "[12/13] Configuring SSH hardening..."

# --- Strat 1: cloud-init override — ii spunem sa scrie PasswordAuthentication yes ---
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-mediasrl-ssh.cfg << 'CLOUDINIT'
# SC MEDIA SRL — Override cloud-init SSH behavior
# ssh_pwauth: true => cloud-init va scrie PasswordAuthentication yes
ssh_pwauth: true
CLOUDINIT
chmod 644 /etc/cloud/cloud.cfg.d/99-mediasrl-ssh.cfg

# --- Strat 2: sshd_config.d/10-mediasrl.conf (prefix 10 < 60 → se citeste primul) ---
cat > /etc/ssh/sshd_config.d/10-mediasrl.conf << 'SSHDCONF'
# SC MEDIA SRL — SSH hardening (prefix 10, se citeste inaintea oricarui fisier 60-*)
PasswordAuthentication yes
PermitRootLogin no
SSHDCONF
chmod 644 /etc/ssh/sshd_config.d/10-mediasrl.conf

# --- Strat 3: sshd_config principal (fallback clasic) ---
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/'   /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/'               /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/'                /etc/ssh/sshd_config

# --- Dezactiveaza cloud-init, configureaza waagent pentru provisioning ---
# cloud-init nu poate fi dezinstalat (walinuxagent depinde de el), dar il oprim
# prin fisierul flag /etc/cloud/cloud-init.disabled. waagent preia provisioningul.
touch /etc/cloud/cloud-init.disabled
echo "  cloud-init disabled via /etc/cloud/cloud-init.disabled"

if [ -f /etc/waagent.conf ]; then
    sed -i 's/^Provisioning.Agent=auto/Provisioning.Agent=waagent/'            /etc/waagent.conf
    sed -i 's/^Provisioning.Enabled=n/Provisioning.Enabled=y/'                 /etc/waagent.conf
    sed -i 's/^Provisioning.UseCloudInit=y/Provisioning.UseCloudInit=n/'       /etc/waagent.conf
    sed -i 's/^Provisioning.MonitorHostName=n/Provisioning.MonitorHostName=y/' /etc/waagent.conf
    grep -q '^Provisioning.Agent'           /etc/waagent.conf || echo 'Provisioning.Agent=waagent'        >> /etc/waagent.conf
    grep -q '^Provisioning.Enabled'         /etc/waagent.conf || echo 'Provisioning.Enabled=y'            >> /etc/waagent.conf
    grep -q '^Provisioning.UseCloudInit'    /etc/waagent.conf || echo 'Provisioning.UseCloudInit=n'       >> /etc/waagent.conf
    grep -q '^Provisioning.MonitorHostName' /etc/waagent.conf || echo 'Provisioning.MonitorHostName=y'    >> /etc/waagent.conf
    echo "  waagent.conf: Provisioning.Agent=waagent, Enabled=y, UseCloudInit=n, MonitorHostName=y"
fi

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

echo "[13/13] Cleaning up..."
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "========================================="
echo "Packer jumphost provisioning complete!"
echo "========================================="
