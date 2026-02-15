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
# STEP 1: System Update
# =============================================================================

echo "[1/5] Updating system packages..."
apt update -qq
apt upgrade -y -qq

# =============================================================================
# STEP 2: Install Common Packages
# =============================================================================
# NOTE: Firewall configuration (ufw) is handled by Ansible roles per VM.
# The base image keeps ufw installed but unconfigured.

echo "[2/5] Installing common packages..."
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

echo "[3/5] Configuring SSH..."
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# =============================================================================
# STEP 4: Configure Timezone
# =============================================================================

echo "[4/5] Setting timezone to Europe/Bucharest..."
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
