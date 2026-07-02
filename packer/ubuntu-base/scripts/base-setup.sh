#!/bin/bash
# ============================================================
# Packer Provisioning Script — Ubuntu 22.04 Base Image
# Basic updates, common packages, SSH hardening for production VMs.
# Role-specific software (nginx, WordPress, etc.) is installed
# by Ansible after deployment.
# ============================================================

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========================================="
echo "Packer: Ubuntu 22.04 Base Image Build"
echo "========================================="

# =============================================================================
# STEP 0: Fix sources.list
# =============================================================================
# Imaginile recente canonical/ubuntu-22_04-lts/server/latest pe Azure migrează
# spre formatul DEB822 (.sources), lăsând uneori linii malformate în
# /etc/apt/sources.list (ex: lipsă prefix 'deb', URL fără tip).
# Reconstruim sources.list cu conținut curat înainte de apt update.

echo "[0/6] Rebuilding /etc/apt/sources.list (fix Azure image DEB822 migration)..."
cat > /etc/apt/sources.list << 'SOURCES'
deb http://azure.archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://azure.archive.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
SOURCES

# Sterge eventualele fisiere .list/.sources conflictuale din sources.list.d
# (pastreaza doar cele specifice Azure: microsoft, azure-cli etc.)
for f in /etc/apt/sources.list.d/ubuntu.sources \
         /etc/apt/sources.list.d/canonical*.list \
         /etc/apt/sources.list.d/ubuntu-esm*.list; do
  [ -f "$f" ] && rm -f "$f" && echo "  Removed conflicting: $f"
done

# =============================================================================
# STEP 1: System Update
# =============================================================================

echo "[1/6] Updating system packages..."
apt update -qq
apt upgrade -y -qq

# =============================================================================
# STEP 2: Install Common + Security Packages
# =============================================================================
# Baked into the image at build-time (was previously installed at runtime by
# Ansible's common role on every deploy). universe/multiverse already enabled
# in STEP 0's sources.list rebuild, so no separate "enable universe" step
# is needed here (unlike the old Ansible task it replaces).

echo "[2/6] Installing common + security packages..."
apt install -y \
    curl wget vim nano htop git \
    unzip zip tar \
    net-tools dnsutils tcpdump telnet rsync \
    jq tree dos2unix \
    ca-certificates gnupg lsb-release \
    python3 python3-apt python3-pip \
    apt-transport-https software-properties-common \
    systemd-timesyncd build-essential \
    fail2ban unattended-upgrades update-notifier-common

# fail2ban must NOT be active during the fragile initial-provisioning window
# (playbooks/1-setup-ssh-keys.yml, first common-role run) — a handful of
# retried/failed SSH attempts during that window could get the jumphost IP
# banned before jails are even configured. Package stays installed (no
# re-download at deploy time); the dedicated fail2ban role (harden-security.yml)
# enables+starts it later, once real jail rules are in place.
systemctl disable --now fail2ban || true

# =============================================================================
# STEP 2b: Remove UFW, install firewalld
# =============================================================================
# Baked into the image (same as ubuntu-jumphost) so Ansible only needs to
# configure zones/ports at runtime, not install/remove packages.

echo "[2b/6] Removing UFW and installing firewalld..."
systemctl stop ufw || true
systemctl disable ufw || true
apt remove -y ufw
apt install -y firewalld
systemctl enable firewalld
systemctl start firewalld

# =============================================================================
# STEP 3: Configure SSH Hardening
# =============================================================================

echo "[3/6] Configuring SSH..."
# Trei straturi de protectie identice cu jumphost-ul:
#
# Strat 1: cloud-init override (ssh_pwauth: true) — cloud-init va scrie
#          PasswordAuthentication yes in 60-cloudimg-settings.conf.
#          Fara acest strat, cloud-init poate reseta la 'no' la primul boot
#          pe Azure gallery images chiar daca Packer a setat 'yes' in imagine.
#
# Strat 2: sshd_config.d/10-mediasrl.conf — prefix "10" < "60", deci se citeste
#          INAINTE de 60-cloudimg-settings.conf. Prima aparitie castiga in sshd.
#
# Strat 3: sshd_config principal (insert before Include) — procesata prima,
#          bate orice fisier din sshd_config.d/.

# --- Strat 1: cloud-init override ---
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-mediasrl-ssh.cfg << 'CLOUDINIT'
# SC MEDIA SRL — Override cloud-init SSH behavior
# ssh_pwauth: true => cloud-init va scrie PasswordAuthentication yes
# in loc de no (comportamentul implicit Azure pentru gallery images)
ssh_pwauth: true
CLOUDINIT
chmod 644 /etc/cloud/cloud.cfg.d/99-mediasrl-ssh.cfg

# --- Strat 2: sshd_config.d/10-mediasrl.conf ---
cat > /etc/ssh/sshd_config.d/10-mediasrl.conf << 'SSHDCONF'
# SC MEDIA SRL — SSH hardening (prefix 10, se citeste inaintea oricarui fisier 60-*)
PasswordAuthentication yes
PermitRootLogin no
SSHDCONF
chmod 644 /etc/ssh/sshd_config.d/10-mediasrl.conf

# --- Strat 3: sshd_config principal (insert before Include) ---
sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
if grep -q '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config; then
    sed -i '/^Include \/etc\/ssh\/sshd_config\.d/i PasswordAuthentication yes' /etc/ssh/sshd_config
else
    sed -i '1i PasswordAuthentication yes' /etc/ssh/sshd_config
fi
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/'  /etc/ssh/sshd_config

# =============================================================================
# STEP 4: Configure Timezone
# =============================================================================

echo "[4/6] Setting timezone to Europe/Bucharest..."
timedatectl set-timezone Europe/Bucharest

# =============================================================================
# STEP 5: Cleanup
# =============================================================================

echo "[5/5] Cleaning up..."
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "========================================="
echo "Packer base image provisioning complete!"
echo "========================================="
