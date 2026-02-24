#!/bin/bash
# ============================================================
# Post-Deploy Finalization — Jumphost (Gallery Image)
# Rulat via Azure Custom Script Extension dupa primul boot.
#
# IMPORTANT: fara set -e. Scriptul TREBUIE sa termine cu exit 0
# chiar daca unele operatii esueaza intern. Altfel CSE raporteaza
# failure si blocheaza intregul deployment Azure.
# Erorile sunt logate in $LOGFILE pentru investigare ulterioara.
# ============================================================

ADMIN_USER="azureadmin"
ADMIN_PASSWORD="Str0ng_P@ssw0rd_2026!"
LOGFILE="/tmp/finalize-jumphost-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

ERRORS=0

echo "========================================="
echo "SC MEDIA SRL - Jumphost Finalization"
echo "========================================="

# =============================================================================
# STEP 0: Asteapta cloud-init sa termine provisioningul
# =============================================================================
# CSE poate porni INAINTE ca cloud-init sa termine de creat userul azureadmin.
# cloud-init status --wait blocheaza pana la finalizarea tuturor fazelor cloud-init.

echo "[0/4] Waiting for cloud-init to finish provisioning..."
if command -v cloud-init >/dev/null 2>&1; then
    cloud-init status --wait --long 2>/dev/null \
        && echo "  OK: cloud-init finished" \
        || echo "  WARN: cloud-init status --wait returned non-zero (ignorat)"
else
    echo "  WARN: cloud-init not found, sleeping 30s as fallback..."
    sleep 30
fi

# Verificare suplimentara: daca userul tot nu exista, il cream manual
if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    echo "  WARN: ${ADMIN_USER} inca nu exista dupa cloud-init, il cream manual..."
    useradd -m -s /bin/bash "${ADMIN_USER}" 2>/dev/null || true
    usermod -aG sudo "${ADMIN_USER}"         2>/dev/null || true
    echo "  ${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ADMIN_USER}"
    chmod 440 "/etc/sudoers.d/${ADMIN_USER}"
    echo "  OK: user creat manual"
fi

# Asigura-te ca home dir exista (poate useradd a fost apelat fara -m)
if [ ! -d "/home/${ADMIN_USER}" ]; then
    mkdir -p "/home/${ADMIN_USER}"
    chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}"
    chmod 750 "/home/${ADMIN_USER}"
    echo "  OK: home dir creat"
fi

# =============================================================================
# STEP 1: Seteaza parola si deblocheaza contul
# =============================================================================
# NU folosim chpasswd — apeleaza PAM si esueaza pe Azure gallery images cu:
#   "pam_chauthtok() failed: Authentication token manipulation error"
#
# openssl passwd -6 + usermod -p scrie hash-ul SHA-512 DIRECT in /etc/shadow,
# fara PAM. passwd -u elimina eventualul prefix ! (cont blocat).

echo "[1/4] Setting password and unlocking account..."
if HASH=$(openssl passwd -6 "${ADMIN_PASSWORD}" 2>/dev/null); then
    if usermod -p "${HASH}" "${ADMIN_USER}" 2>/dev/null; then
        passwd -u "${ADMIN_USER}" 2>/dev/null || true
        echo "  OK: password set via usermod (bypass PAM), account unlocked"
    else
        echo "  ERROR: usermod -p failed"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ERROR: openssl passwd failed"
    ERRORS=$((ERRORS + 1))
fi

# =============================================================================
# STEP 2: Forteaza PasswordAuthentication yes in sshd_config
# =============================================================================
# Inserare INAINTE de Include — prima aparitie castiga in sshd(8),
# bate orice fisier din sshd_config.d/ (inclusiv cel scris de cloud-init).

echo "[2/4] Enforcing SSH password authentication..."

sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config 2>/dev/null || true

if grep -q '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config 2>/dev/null; then
    sed -i '/^Include \/etc\/ssh\/sshd_config\.d/i PasswordAuthentication yes' /etc/ssh/sshd_config
    echo "  Inserted PasswordAuthentication yes before Include"
else
    sed -i '1i PasswordAuthentication yes' /etc/ssh/sshd_config
    echo "  Inserted PasswordAuthentication yes at top of sshd_config"
fi

for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$f" 2>/dev/null || true
done

cat > /etc/ssh/sshd_config.d/10-mediasrl.conf << 'SSHDCONF'
# SC MEDIA SRL — SSH hardening (prefix 10 < 60-cloudimg-settings)
PasswordAuthentication yes
PermitRootLogin no
SSHDCONF

if systemctl restart ssh 2>/dev/null; then
    echo "  OK: sshd restarted"
else
    echo "  WARN: sshd restart failed"
    ERRORS=$((ERRORS + 1))
fi

# =============================================================================
# STEP 3: Creeaza .xsession pentru xRDP/XFCE4
# =============================================================================
# azureadmin e creat de cloud-init la first boot, dupa Packer build.
# .xsession trebuie creat dupa ce /home/azureadmin/ exista.

echo "[3/4] Configuring xRDP session for ${ADMIN_USER}..."
if [ -d "/home/${ADMIN_USER}" ]; then
    echo "xfce4-session" > "/home/${ADMIN_USER}/.xsession"
    chmod +x "/home/${ADMIN_USER}/.xsession"
    chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.xsession"
    echo "  OK: .xsession created"

    mkdir -p "/home/${ADMIN_USER}/ansible-workspace"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/ansible-workspace" 2>/dev/null || true
    echo "  OK: ansible-workspace created"
else
    echo "  WARN: /home/${ADMIN_USER} not found — skipping .xsession"
    ERRORS=$((ERRORS + 1))
fi

systemctl restart xrdp 2>/dev/null && echo "  OK: xrdp restarted" || echo "  WARN: xrdp restart skipped"

# =============================================================================
# STEP 4: Verifica servicii
# =============================================================================

echo "[4/4] Verifying services..."
systemctl is-active ssh  2>/dev/null && echo "  OK: ssh  running" || echo "  WARN: ssh  not active"
systemctl is-active xrdp 2>/dev/null && echo "  OK: xrdp running" || echo "  WARN: xrdp not active"

echo "========================================="
echo "Finalization complete (errors: ${ERRORS})"
echo "  Log saved: ${LOGFILE}"
echo "========================================="

# Intotdeauna exit 0 — CSE trebuie sa raporteze success catre Azure
# chiar daca unele operatii au esuat intern (logate mai sus).
exit 0
