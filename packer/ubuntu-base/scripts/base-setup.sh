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

# Fallback: editeaza si sshd_config principal
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/'   /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/'               /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/'                /etc/ssh/sshd_config

# =============================================================================
# STEP 4: Configure Timezone
# =============================================================================

echo "[4/6] Setting timezone to Europe/Bucharest..."
timedatectl set-timezone Europe/Bucharest

# =============================================================================
# STEP 5: Cleanup
# =============================================================================


# =============================================================================
# STEP 5: Dezactiveaza cloud-init, configureaza waagent pentru provisioning
# =============================================================================
# cloud-init nu poate fi dezinstalat pe Ubuntu 22.04 (walinuxagent depinde de el).
# In schimb, il dezactivam prin fisierul flag /etc/cloud/cloud-init.disabled.
# waagent preia provisioningul: SSH key injection, hostname, disk resize.

echo "[5/6] Disabling cloud-init, configuring waagent..."

# Dezactiveaza cloud-init — prezenta acestui fisier opreste cloud-init la boot
touch /etc/cloud/cloud-init.disabled
echo "  cloud-init disabled via /etc/cloud/cloud-init.disabled"

# Configureaza waagent sa preia provisioningul (nu cloud-init)
if [ -f /etc/waagent.conf ]; then
    sed -i 's/^Provisioning.Agent=auto/Provisioning.Agent=waagent/'       /etc/waagent.conf
    sed -i 's/^Provisioning.Enabled=n/Provisioning.Enabled=y/'            /etc/waagent.conf
    sed -i 's/^Provisioning.UseCloudInit=y/Provisioning.UseCloudInit=n/'  /etc/waagent.conf
    sed -i 's/^Provisioning.MonitorHostName=n/Provisioning.MonitorHostName=y/' /etc/waagent.conf
    grep -q '^Provisioning.Agent'        /etc/waagent.conf || echo 'Provisioning.Agent=waagent'    >> /etc/waagent.conf
    grep -q '^Provisioning.Enabled'      /etc/waagent.conf || echo 'Provisioning.Enabled=y'        >> /etc/waagent.conf
    grep -q '^Provisioning.UseCloudInit' /etc/waagent.conf || echo 'Provisioning.UseCloudInit=n'   >> /etc/waagent.conf
    grep -q '^Provisioning.MonitorHostName' /etc/waagent.conf || echo 'Provisioning.MonitorHostName=y' >> /etc/waagent.conf
    echo "  waagent.conf: Provisioning.Agent=waagent, Enabled=y, UseCloudInit=n, MonitorHostName=y"
fi

echo "[6/6] Cleaning up..."
apt autoremove -y
apt clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "========================================="
echo "Packer base image provisioning complete!"
echo "========================================="
