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
# STEP 2: Install Common Packages
# =============================================================================
# NOTE: Firewall configuration (ufw) is handled by Ansible roles per VM.
# The base image keeps ufw installed but unconfigured.

echo "[2/6] Installing common packages..."
apt install -y \
    curl wget vim nano \
    net-tools dnsutils \
    jq tree unzip \
    ca-certificates gnupg lsb-release \
    python3 python3-apt \
    apt-transport-https software-properties-common

# =============================================================================
# STEP 3: Configure SSH Hardening
# =============================================================================

echo "[3/6] Configuring SSH..."
# sshd_config.d: fisierele se citesc alfabetic, PRIMA aparitie castiga.
# "10-mediasrl.conf" se citeste INAINTE de "60-cloudimg-settings.conf" (creat de
# cloud-init la primul boot). Astfel PasswordAuthentication yes castiga intotdeauna.
cat > /etc/ssh/sshd_config.d/10-mediasrl.conf << 'SSHDCONF'
# SC MEDIA SRL — SSH hardening (prioritate maxima, prefixul 10 < 60-cloudimg-settings)
PasswordAuthentication yes
PermitRootLogin no
SSHDCONF
chmod 644 /etc/ssh/sshd_config.d/10-mediasrl.conf

# Forteaza PasswordAuthentication yes INAINTE de Include in sshd_config principal.
# Prima aparitie a unui parametru castiga in sshd(8) — deci aceasta setare bate
# orice fisier din sshd_config.d/ (inclusiv 60-cloudimg-settings.conf de cloud-init).
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
