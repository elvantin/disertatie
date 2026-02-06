#!/bin/bash
# ============================================================
# Bootstrap Script for Jumphost (Rocky Linux)
# Installs xRDP, enables password auth, configures firewall
# ============================================================

set -e

echo "========================================="
echo "Starting jumphost bootstrap..."
echo "========================================="

# Set password for azureadmin user
ADMIN_USER="azureadmin"
ADMIN_PASSWORD="Str0ng_P@ssw0rd_2026!"

echo "Setting password for ${ADMIN_USER}..."
echo "${ADMIN_USER}:${ADMIN_PASSWORD}" | chpasswd

# Enable password authentication in SSH config
echo "Enabling password authentication..."
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# Install EPEL repository
echo "Installing EPEL repository..."
dnf install -y epel-release

# Install xRDP
echo "Installing xRDP..."
dnf install -y xrdp xrdp-selinux

# Configure xRDP
echo "Configuring xRDP..."
systemctl enable xrdp
systemctl start xrdp

# Configure firewall
echo "Configuring firewall for RDP (port 3389)..."
firewall-cmd --permanent --add-port=3389/tcp
firewall-cmd --reload

# Configure SELinux for xRDP
echo "Configuring SELinux for xRDP..."
setsebool -P xrdp_can_network_connect 1

# Install basic GUI (lightweight XFCE instead of full GNOME for faster boot)
echo "Installing XFCE Desktop Environment..."
dnf groupinstall -y "Xfce" "base-x"

# Set graphical target
systemctl set-default graphical.target

# Create xsession file for user
echo "Configuring desktop session..."
echo "xfce4-session" > /home/${ADMIN_USER}/.Xclients
chmod +x /home/${ADMIN_USER}/.Xclients
chown ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.Xclients

# Install basic tools
echo "Installing DevOps tools..."
dnf install -y \
    git \
    vim \
    wget \
    curl \
    htop \
    tmux \
    net-tools \
    bind-utils \
    tcpdump \
    nmap \
    telnet \
    nc \
    jq \
    tree

echo "========================================="
echo "Bootstrap complete!"
echo "You can now connect via RDP:"
echo "  Address: <jumphost-public-ip>:3389"
echo "  Username: ${ADMIN_USER}"
echo "  Password: ${ADMIN_PASSWORD}"
echo "========================================="

# Reboot to apply all changes
echo "Rebooting system to apply changes..."
sleep 5
reboot
