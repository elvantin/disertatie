#!/bin/bash
# ============================================================
# Packer Provisioning Script — Ubuntu 22.04 Jumphost Image
# Installs XFCE Desktop, xRDP, Ansible, Azure CLI, DevOps tools,
# Ansible Galaxy Collections (pre-baked, no post-deploy install needed)
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

echo "[0/15] Rebuilding /etc/apt/sources.list (fix Azure image DEB822 migration)..."
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

echo "[1/15] Updating system packages..."
apt update -qq
apt upgrade -y -qq

# =============================================================================
# STEP 2: Install Firewalld (replace UFW)
# =============================================================================

echo "[2/15] Removing UFW and installing firewalld..."
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

echo "[3/15] Installing XFCE Desktop Environment..."
apt install -y xfce4 xfce4-goodies

echo "[4/15] Installing X11 components..."
apt install -y xorg dbus-x11 x11-xserver-utils xterm

systemctl set-default graphical.target

# =============================================================================
# STEP 4: Install and Configure xRDP
# =============================================================================

echo "[5/15] Installing and configuring xRDP..."
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

echo "[6/15] Installing Remmina..."
apt-add-repository -y ppa:remmina-ppa-team/remmina-next
apt update -qq
apt install -y remmina remmina-plugin-rdp remmina-plugin-secret

# =============================================================================
# STEP 6: Install Ansible and Configuration Management Tools
# =============================================================================

echo "[7/15] Installing Ansible and dependencies..."
apt install -y software-properties-common
add-apt-repository --yes --update ppa:ansible/ansible
apt install -y ansible python3-pip python3-winrm python3-requests sshpass

# =============================================================================
# STEP 7: Install Azure CLI
# =============================================================================

echo "[8/15] Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# =============================================================================
# STEP 8: Install Ansible Galaxy Collections
# =============================================================================
# Pre-bake all required collections into the golden image so that:
#   - No internet access needed on first playbook run
#   - deploy-ansible-to-jumphost.ps1 uses requirements.yml for version pinning
#
# Collections installed to /usr/share/ansible/collections (system-wide, accessible to all users).
# ansible.cfg on jumphost has collections_path = ./collections:~/ansible/collections:/usr/share/ansible/collections
#   ansible.windows    — win_firewall, win_updates, win_feature, win_shell, win_service_info
#   ansible.posix      — authorized_key, firewalld
#   community.general  — ufw, ini_file, profile_tasks callback
#                        NOTE: Pinned <12.0.0 — v12.0.0 removed the yaml callback
#                        tombstone which triggers a fatal ERROR with bin_ansible_callbacks=True
#   community.windows  — win_domain_membership, win_scheduled_task
#   azure.azcollection — azure_rm dynamic inventory plugin (auth_source: msi via SystemAssigned MSI)

COLLECTIONS_INSTALL_PATH="/usr/share/ansible/collections"
mkdir -p "${COLLECTIONS_INSTALL_PATH}"

echo "[9/15] Installing Ansible Galaxy collections..."
ansible-galaxy collection install \
    "ansible.windows" \
    "ansible.posix" \
    "community.general:>=8.0.0,<12.0.0" \
    "community.windows" \
    "azure.azcollection:>=3.15.0" \
    --collections-path "${COLLECTIONS_INSTALL_PATH}" \
    --force

# Install Python requirements for azure.azcollection (needed for dynamic inventory + modules)
AZURE_COLL="${COLLECTIONS_INSTALL_PATH}/ansible_collections/azure/azcollection"
if [ -f "${AZURE_COLL}/requirements.txt" ]; then
    echo "  Installing Python requirements for azure.azcollection..."
    pip3 install -r "${AZURE_COLL}/requirements.txt" --quiet 2>&1 | tail -5
fi

# azure-identity is required for auth_source: msi (ManagedIdentityCredential via Azure IMDS).
# Also present in azcollection requirements.txt, but pinned explicitly for reliability.
pip3 install "azure-identity>=1.16.0" --upgrade --quiet 2>&1 | tail -3
echo "  OK: Galaxy collections + Python dependencies installed"

# =============================================================================
# STEP 9: Install Visual Studio Code
# =============================================================================

echo "[10/15] Installing Visual Studio Code..."
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

echo "[11/15] Installing Firefox ESR..."
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

echo "[12/15] Installing DevOps tools..."
apt install -y \
    git vim nano mc wget curl htop tmux screen \
    net-tools dnsutils tcpdump nmap telnet netcat \
    jq tree bash-completion unzip zip tar build-essential \
    mysql-client-core-8.0 smbclient

# =============================================================================
# STEP 13: Install gnome-keyring and MySQL Workbench Community
# =============================================================================
# gnome-keyring: required by MySQL Workbench to store connection passwords securely
# MySQL Workbench: direct CDN download — same approach as the Windows MSI installer
#   dev.mysql.com/downloads/workbench/ -> "No thanks, just start my download"
#   resolves to cdn.mysql.com CDN URL (no Oracle account required)
# =============================================================================

echo "[13/15] Installing gnome-keyring and MySQL Workbench Community..."

# gnome-keyring + secret service (needed by Workbench for password storage)
apt install -y gnome-keyring libsecret-1-0 libsecret-tools seahorse

# MySQL Workbench Community for Ubuntu 22.04 — direct CDN download
WORKBENCH_VERSION="8.0.46"
WORKBENCH_DEB="mysql-workbench-community_${WORKBENCH_VERSION}-1ubuntu22.04_amd64.deb"
WORKBENCH_URL="https://cdn.mysql.com//Downloads/MySQLGUITools/${WORKBENCH_DEB}"

echo "  Downloading MySQL Workbench ${WORKBENCH_VERSION} from MySQL CDN..."
wget -O "/tmp/${WORKBENCH_DEB}" "${WORKBENCH_URL}"

# apt install (not dpkg) resolves dependencies automatically from Ubuntu repos
echo "  Installing MySQL Workbench and dependencies..."
DEBIAN_FRONTEND=noninteractive apt install -y "/tmp/${WORKBENCH_DEB}" || {
    echo "  Direct apt install failed, falling back to dpkg + apt -f fix..."
    dpkg -i "/tmp/${WORKBENCH_DEB}" || true
    apt install -f -y
}

rm -f "/tmp/${WORKBENCH_DEB}"
echo "  MySQL Workbench ${WORKBENCH_VERSION} installed successfully."

# =============================================================================
# STEP 13b: Pre-configure MySQL Workbench and Remmina connections in /etc/skel
# =============================================================================
# Files placed in /etc/skel/ are automatically copied to new user home
# directories when the account is created by cloud-init on Azure provisioning.
# This ensures connections are ready when azureadmin first logs in via RDP.
# =============================================================================

echo "[13b] Pre-configuring MySQL Workbench and Remmina connections in /etc/skel..."

# ── MySQL Workbench: connection "db" → vm-db-01:3306, user root, no saved password ──
# Password is intentionally omitted — user enters it on first connection.
mkdir -p /etc/skel/.mysql/workbench
chmod 755 /etc/skel/.mysql /etc/skel/.mysql/workbench
cat > /etc/skel/.mysql/workbench/connections.xml << 'MWBCONN'
<?xml version="1.0"?>
<data grt_format="2.0" source_version="8.0.46">
  <value type="list" content-type="object" content-struct-name="db.mgmt.Connection">
    <value type="object" struct-name="db.mgmt.Connection" id="a1b2c3d4-1001-1001-1001-000000000001" struct-checksum="0x96ba47d8">
      <link type="object" struct-name="db.mgmt.Driver" key="driver">com.mysql.rdbms.mysql</link>
      <value type="string" key="hostIdentifier">Mysql@vm-db-01:3306</value>
      <value type="string" key="isDefault">0</value>
      <value type="dict" key="parameterValues">
        <value type="string" key="PORT">3306</value>
        <value type="string" key="SERVER">vm-db-01</value>
        <value type="string" key="hostName">vm-db-01</value>
        <value type="string" key="password"></value>
        <value type="string" key="port">3306</value>
        <value type="string" key="schema"></value>
        <value type="string" key="sslCA"></value>
        <value type="string" key="sslCert"></value>
        <value type="string" key="sslKey"></value>
        <value type="string" key="useSSL">0</value>
        <value type="string" key="userName">root</value>
      </value>
      <value type="string" key="name">db</value>
      <value type="string" key="description">MySQL on vm-db-01 (port 3306)</value>
    </value>
  </value>
</data>
MWBCONN
chmod 644 /etc/skel/.mysql/workbench/connections.xml

# ── Remmina preferences: use null plugin so passwords are stored in profile files ──
# remmina-plugin-secret (installed above) defaults to gnome-keyring which requires
# a live keyring session. Setting secret_plugin=remmina-plugin-null stores passwords
# directly in the .remmina profile files — simpler and works without a keyring session.
mkdir -p /etc/skel/.config/remmina
chmod 700 /etc/skel/.config /etc/skel/.config/remmina
cat > /etc/skel/.config/remmina/remmina.pref << 'REMMINPREF'
[remmina]
secret_plugin=remmina-plugin-null
scale_quality=0
toolbar_pin_down=0
grab_color_scheme=default
REMMINPREF
chmod 600 /etc/skel/.config/remmina/remmina.pref

# ── Remmina RDP profiles ──
mkdir -p /etc/skel/.local/share/remmina
chmod 755 /etc/skel/.local /etc/skel/.local/share /etc/skel/.local/share/remmina

cat > /etc/skel/.local/share/remmina/db.remmina << 'REMMDB'
[remmina]
name=db
group=
server=vm-db-01
protocol=RDP
username=azureadmin
password=
domain=
resolution_mode=2
width=1280
height=960
colordepth=32
scale=1
keyboard_grab=0
window_maximize=0
window_width=1280
window_height=960
sound=off
ssh_loopback=0
REMMDB
chmod 600 /etc/skel/.local/share/remmina/db.remmina

cat > /etc/skel/.local/share/remmina/fs.remmina << 'REMMFS'
[remmina]
name=fs
group=
server=vm-fs-01
protocol=RDP
username=azureadmin
password=
domain=
resolution_mode=2
width=1280
height=960
colordepth=32
scale=1
keyboard_grab=0
window_maximize=0
window_width=1280
window_height=960
sound=off
ssh_loopback=0
REMMFS
chmod 600 /etc/skel/.local/share/remmina/fs.remmina

# ── XFCE4 Screensaver: idle timeout = 59 minutes, screen lock disabled ──
# xfce4-screensaver reads xfconf XML at session start.
# delay is in minutes. Lock disabled — useful for RDP sessions on a secured VNet.
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
chmod 755 /etc/skel/.config/xfce4 \
          /etc/skel/.config/xfce4/xfconf \
          /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml << 'SCREENSAVER'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="true"/>
    <property name="idle-activation" type="empty">
      <property name="enabled" type="bool" value="true"/>
      <property name="delay" type="int" value="59"/>
    </property>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
SCREENSAVER
chmod 644 /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml

echo "  MySQL Workbench connection 'db' → vm-db-01:3306 (user: root)"
echo "  Remmina RDP 'db' → vm-db-01 (azureadmin, 1280x960)"
echo "  Remmina RDP 'fs' → vm-fs-01 (azureadmin, 1280x960)"
echo "  XFCE screensaver idle timeout: 59 minutes"

# =============================================================================
# STEP 14: Configurare SSH hardening
# =============================================================================
# cloud-init ruleaza normal (necesar pentru Azure provisioning — hostname, SSH key
# injection, disk resize). Controlam SSH prin doua straturi de prioritate:
#
# Strat 1: cloud-init override (ssh_pwauth: true) — cloud-init scrie
#          PasswordAuthentication yes in 60-cloudimg-settings.conf (nu no).
#
# Strat 2: sshd_config.d/10-mediasrl.conf — prefix "10" < "60", deci se citeste
#          INAINTE de 60-cloudimg-settings.conf. Prima aparitie castiga in sshd.
#          Chiar daca cloud-init ignora override-ul, al nostru castiga oricum.
#
# Accesul SSH ramane sigur prin NSG (portul 22 whitelist pe IP-ul admin).

echo "[14/15] Configuring SSH hardening..."

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

# --- Strat 3: sshd_config principal (insert before Include — prima aparitie castiga) ---
# Aceasta setare e procesata INAINTE de orice fisier din sshd_config.d/,
# inclusiv 60-cloudimg-settings.conf scris de cloud-init la primul boot.
sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
if grep -q '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config; then
    sed -i '/^Include \/etc\/ssh\/sshd_config\.d/i PasswordAuthentication yes' /etc/ssh/sshd_config
else
    sed -i '1i PasswordAuthentication yes' /etc/ssh/sshd_config
fi
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/'  /etc/ssh/sshd_config

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
- MySQL Workbench 8.0.46 (connect to vm-db-01:3306)
- DevOps utilities (htop, tmux, jq, etc.)

Ansible Galaxy Collections (pre-installed):
- ansible.windows, ansible.posix
- community.general (<12.0.0), community.windows
- azure.azcollection (dynamic inventory)

Quick Commands:
  ansible --version
  az --version
  az login

==========================================
MOTD_EOF

# =============================================================================
# STEP 15: Cleanup
# =============================================================================

echo "[15/15] Cleaning up..."
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "========================================="
echo "Packer jumphost provisioning complete!"
echo "========================================="
