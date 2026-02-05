#!/bin/bash
# ============================================================
# Base Setup — Rocky Linux 10 Golden Image
# Installs common packages, enables essential services,
# and prepares the OS for role-specific Ansible configuration.
# ============================================================
set -euo pipefail

echo "========================================="
echo " Rocky Linux 10 — Base Setup"
echo "========================================="

# ----- System Update -----
echo "[1/6] Updating all system packages..."
dnf update -y

# ----- EPEL Repository -----
echo "[2/6] Installing EPEL repository..."
dnf install -y epel-release

# ----- Common Packages -----
echo "[3/6] Installing common packages..."
dnf install -y \
  curl \
  wget \
  vim-enhanced \
  git \
  unzip \
  tar \
  net-tools \
  bind-utils \
  traceroute \
  tcpdump \
  htop \
  tree \
  jq \
  rsync \
  tmux \
  bash-completion \
  man-pages \
  openssh-server \
  openssh-clients \
  python3 \
  python3-pip

# ----- Security & Compliance Packages -----
echo "[4/6] Installing security packages..."
dnf install -y \
  firewalld \
  policycoreutils-python-utils \
  setools-console \
  aide \
  chrony \
  audit \
  audit-libs

# ----- Enable Essential Services -----
echo "[5/6] Enabling essential services..."
systemctl enable firewalld
systemctl enable chronyd
systemctl enable sshd
systemctl enable auditd

# ----- Cleanup -----
echo "[6/6] Cleaning up..."
dnf clean all
rm -rf /var/cache/dnf
rm -rf /tmp/* /var/tmp/*

echo "========================================="
echo " Base Setup Complete"
echo "========================================="
