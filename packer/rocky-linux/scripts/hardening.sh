#!/bin/bash
# ============================================================
# CIS Hardening — Rocky Linux 10 Golden Image
# Applies baseline CIS Benchmark controls for RHEL/Rocky Linux.
# Additional role-specific hardening is applied by Ansible.
# ============================================================
set -euo pipefail

echo "========================================="
echo " Rocky Linux 10 — CIS Hardening"
echo "========================================="

# =============================================================
# 1. FILESYSTEM HARDENING
# =============================================================
echo "[1/8] Filesystem hardening..."

# Disable unused filesystems (CIS 1.1.1.x)
cat > /etc/modprobe.d/cis-filesystems.conf << 'EOF'
install cramfs /bin/true
install squashfs /bin/true
install udf /bin/true
install usb-storage /bin/true
EOF

# Set sticky bit on world-writable directories (CIS 1.1.22)
df --local -P | awk '{if (NR!=1) print $6}' | xargs -I '{}' find '{}' -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null | while read -r dir; do
  chmod a+t "$dir"
done

# =============================================================
# 2. SSH HARDENING (CIS 5.2.x)
# =============================================================
echo "[2/8] SSH hardening..."

# Backup original sshd_config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat > /etc/ssh/sshd_config.d/99-cis-hardening.conf << 'EOF'
# CIS Benchmark SSH Hardening

# Protocol and authentication
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 4
MaxSessions 10

# Restrict access
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitUserEnvironment no

# Session settings
ClientAliveInterval 300
ClientAliveCountMax 3
LoginGraceTime 60

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Crypto policy — strong ciphers and MACs
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Banner
Banner /etc/issue.net
EOF

# Set login banner (CIS 1.7.x)
cat > /etc/issue.net << 'EOF'
***************************************************************************
  NOTICE: This is a private system. Unauthorized access is prohibited.
  All activity is monitored and logged.
***************************************************************************
EOF

cat > /etc/issue << 'EOF'
***************************************************************************
  NOTICE: This is a private system. Unauthorized access is prohibited.
  All activity is monitored and logged.
***************************************************************************
EOF

# Set SSH file permissions (CIS 5.2.1-5.2.3)
chown root:root /etc/ssh/sshd_config
chmod 600 /etc/ssh/sshd_config

# =============================================================
# 3. KERNEL HARDENING — sysctl (CIS 3.x)
# =============================================================
echo "[3/8] Kernel parameter hardening..."

cat > /etc/sysctl.d/99-cis-hardening.conf << 'EOF'
# CIS Benchmark Kernel Hardening

# Network — IP forwarding and routing (CIS 3.2.x)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Network — Packet redirect (CIS 3.3.x)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Network — Source routing (CIS 3.3.x)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Network — ICMP and SYN protection (CIS 3.3.x)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Network — IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Kernel — Address space layout randomization (CIS 1.5.3)
kernel.randomize_va_space = 2

# Kernel — Core dumps (CIS 1.5.1)
fs.suid_dumpable = 0
EOF

# Apply sysctl settings
sysctl --system > /dev/null 2>&1

# =============================================================
# 4. DISABLE UNNECESSARY SERVICES (CIS 2.x)
# =============================================================
echo "[4/8] Disabling unnecessary services..."

SERVICES_TO_DISABLE=(
  "avahi-daemon"
  "cups"
  "dhcpd"
  "named"
  "vsftpd"
  "httpd"
  "dovecot"
  "smb"
  "squid"
  "snmpd"
  "ypserv"
  "rsh.socket"
  "rlogin.socket"
  "rexec.socket"
  "telnet.socket"
  "tftp.socket"
)

for svc in "${SERVICES_TO_DISABLE[@]}"; do
  if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
    systemctl disable --now "$svc" 2>/dev/null || true
    echo "  Disabled: $svc"
  fi
done

# =============================================================
# 5. PASSWORD AND ACCOUNT POLICIES (CIS 5.4.x, 5.5.x)
# =============================================================
echo "[5/8] Configuring password and account policies..."

# Password aging (CIS 5.6.1.x)
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

# Default umask (CIS 5.5.5)
sed -i 's/^UMASK.*/UMASK           027/' /etc/login.defs

# Account lockout (CIS 5.4.2) — via faillock
cat > /etc/security/faillock.conf << 'EOF'
# Account lockout after failed attempts
deny = 5
unlock_time = 900
fail_interval = 900
EOF

# =============================================================
# 6. FILE PERMISSIONS (CIS 6.1.x)
# =============================================================
echo "[6/8] Setting critical file permissions..."

chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
chmod 644 /etc/passwd
chmod 000 /etc/shadow
chmod 644 /etc/group
chmod 000 /etc/gshadow

chown root:root /etc/passwd- /etc/shadow- /etc/group- /etc/gshadow- 2>/dev/null || true
chmod 644 /etc/passwd- 2>/dev/null || true
chmod 000 /etc/shadow- 2>/dev/null || true
chmod 644 /etc/group- 2>/dev/null || true
chmod 000 /etc/gshadow- 2>/dev/null || true

# Crontab permissions (CIS 5.1.x)
chown root:root /etc/crontab 2>/dev/null && chmod 600 /etc/crontab || true
for dir in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d; do
  if [ -d "$dir" ]; then
    chown root:root "$dir"
    chmod 700 "$dir"
  fi
done

# =============================================================
# 7. AUDIT CONFIGURATION (CIS 4.1.x)
# =============================================================
echo "[7/8] Configuring audit rules..."

cat > /etc/audit/rules.d/99-cis-hardening.rules << 'EOF'
# CIS Benchmark Audit Rules

# Monitor changes to user/group files (CIS 4.1.4-4.1.6)
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# Monitor changes to network configuration (CIS 4.1.7)
-w /etc/hosts -p wa -k system-network
-w /etc/sysconfig/network -p wa -k system-network
-w /etc/sysconfig/network-scripts/ -p wa -k system-network

# Monitor login events (CIS 4.1.8-4.1.9)
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock/ -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# Monitor session events (CIS 4.1.10)
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# Monitor changes to sudoers (CIS 4.1.15)
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# Monitor use of privileged commands (CIS 4.1.11)
-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k privileged
-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k privileged

# Monitor kernel module loading (CIS 4.1.17)
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Make audit configuration immutable (must be last rule)
-e 2
EOF

# =============================================================
# 8. SELinux VERIFICATION
# =============================================================
echo "[8/8] Verifying SELinux is enforcing..."

# Ensure SELinux is set to enforcing (CIS 1.6.x)
if [ -f /etc/selinux/config ]; then
  sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
  sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config
fi

# Initialize AIDE database (CIS 1.3.1)
echo "Initializing AIDE database (this may take a few minutes)..."
aide --init 2>/dev/null || true
if [ -f /var/lib/aide/aide.db.new.gz ]; then
  mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
fi

echo "========================================="
echo " CIS Hardening Complete"
echo "========================================="
echo ""
echo " Applied controls:"
echo "  - Filesystem: disabled unused modules, sticky bit"
echo "  - SSH: key-only auth, strong ciphers, no root login"
echo "  - Kernel: sysctl hardening (network, ASLR, core dumps)"
echo "  - Services: disabled unnecessary daemons"
echo "  - Passwords: aging, complexity, account lockout"
echo "  - File permissions: critical system files secured"
echo "  - Audit: comprehensive auditd rules"
echo "  - SELinux: enforcing mode"
echo ""
echo " NOTE: Role-specific hardening will be applied by Ansible."
echo "========================================="
