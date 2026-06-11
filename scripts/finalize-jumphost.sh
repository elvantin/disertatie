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
# Placeholder replaced by bicep/main.bicep replace() at deployment time.
# The real value comes from az.getSecret() in .bicepparam -> kv-mediasrl-persistent.
ADMIN_PASSWORD="__ADMIN_PASSWORD_PLACEHOLDER__"
LOGFILE="/tmp/finalize-jumphost-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

ERRORS=0
_TS=$(date +%s)
_OK=0; _FAIL=0; _WARN=0

# Inline log helpers (no lib available in CSE context)
_C_CYAN='\033[0;36m'; _C_GREEN='\033[0;32m'; _C_RED='\033[0;31m'
_C_YELLOW='\033[1;33m'; _C_GRAY='\033[0;37m'; _C_BOLD='\033[1m'; _C_RST='\033[0m'
_log_ok()   { echo -e "${_C_GREEN}  [OK] $*${_C_RST}";   _OK=$((_OK+1)); }
_log_warn() { echo -e "${_C_YELLOW}  [!]  $*${_C_RST}";  _WARN=$((_WARN+1)); }
_log_fail() { echo -e "${_C_RED}  [!!] $*${_C_RST}";     _FAIL=$((_FAIL+1)); ERRORS=$((ERRORS+1)); }
_log_step() { echo -e "${_C_YELLOW}  [>>] $*${_C_RST}"; }
_log_info() { echo -e "${_C_GRAY}       $*${_C_RST}"; }

_SEP=$(printf '%.0s=' {1..58})
echo ""
echo -e "${_C_CYAN}  ${_SEP}${_C_RST}"
echo -e "${_C_BOLD}  SC MEDIA SRL — Jumphost Finalization${_C_RST}"
echo -e "${_C_GRAY}  $(date '+%Y-%m-%d %H:%M:%S')  ·  CSE post-boot script${_C_RST}"
echo -e "${_C_GRAY}  Log: $LOGFILE${_C_RST}"
echo -e "${_C_CYAN}  ${_SEP}${_C_RST}"

# =============================================================================
# STEP 0: Asteapta cloud-init sa termine provisioningul
# =============================================================================
# CSE poate porni INAINTE ca cloud-init sa termine de creat userul azureadmin.
# cloud-init status --wait blocheaza pana la finalizarea tuturor fazelor cloud-init.

echo ""
_log_step "[0/4] Așteptare cloud-init..."
if command -v cloud-init >/dev/null 2>&1; then
    cloud-init status --wait --long 2>/dev/null \
        && _log_ok "cloud-init finalizat" \
        || _log_warn "cloud-init --wait returned non-zero (ignorat)"
else
    _log_warn "cloud-init nu există, sleep 30s ca fallback..."
    sleep 30
fi

if ! id "${ADMIN_USER}" >/dev/null 2>&1; then
    _log_warn "${ADMIN_USER} nu există după cloud-init — creare manuală..."
    useradd -m -s /bin/bash "${ADMIN_USER}" 2>/dev/null || true
    usermod -aG sudo "${ADMIN_USER}"         2>/dev/null || true
    echo "  ${ADMIN_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${ADMIN_USER}"
    chmod 440 "/etc/sudoers.d/${ADMIN_USER}"
    _log_ok "User ${ADMIN_USER} creat manual"
fi

if [ ! -d "/home/${ADMIN_USER}" ]; then
    mkdir -p "/home/${ADMIN_USER}"
    chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}"
    chmod 750 "/home/${ADMIN_USER}"
    _log_ok "Home dir creat: /home/${ADMIN_USER}"
fi

# =============================================================================
# STEP 1: Seteaza parola si deblocheaza contul
# =============================================================================
# NU folosim chpasswd — apeleaza PAM si esueaza pe Azure gallery images cu:
#   "pam_chauthtok() failed: Authentication token manipulation error"
#
# openssl passwd -6 + usermod -p scrie hash-ul SHA-512 DIRECT in /etc/shadow,
# fara PAM. passwd -u elimina eventualul prefix ! (cont blocat).

echo ""
_log_step "[1/4] Setare parolă și deblocare cont..."
if HASH=$(openssl passwd -6 "${ADMIN_PASSWORD}" 2>/dev/null); then
    if usermod -p "${HASH}" "${ADMIN_USER}" 2>/dev/null; then
        passwd -u "${ADMIN_USER}" 2>/dev/null || true
        _log_ok "Parolă setată via usermod (bypass PAM), cont deblocat"
    else
        _log_fail "usermod -p a eșuat"
    fi
else
    _log_fail "openssl passwd a eșuat"
fi

# =============================================================================
# STEP 2: Forteaza PasswordAuthentication yes in sshd_config
# =============================================================================
# Inserare INAINTE de Include — prima aparitie castiga in sshd(8),
# bate orice fisier din sshd_config.d/ (inclusiv cel scris de cloud-init).

echo ""
_log_step "[2/4] Activare SSH password authentication..."

sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config 2>/dev/null || true

if grep -q '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config 2>/dev/null; then
    sed -i '/^Include \/etc\/ssh\/sshd_config\.d/i PasswordAuthentication yes' /etc/ssh/sshd_config
    _log_info "PasswordAuthentication yes inserat înainte de Include"
else
    sed -i '1i PasswordAuthentication yes' /etc/ssh/sshd_config
    _log_info "PasswordAuthentication yes inserat la începutul sshd_config"
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
    _log_ok "sshd restartat cu PasswordAuthentication=yes, PermitRootLogin=no"
else
    _log_warn "sshd restart eșuat"
fi

# =============================================================================
# STEP 3: Creeaza .xsession pentru xRDP/XFCE4
# =============================================================================
# azureadmin e creat de cloud-init la first boot, dupa Packer build.
# .xsession trebuie creat dupa ce /home/azureadmin/ exista.

echo ""
_log_step "[3/4] Configurare sesiune xRDP/XFCE4 pentru ${ADMIN_USER}..."
if [ -d "/home/${ADMIN_USER}" ]; then
    echo "xfce4-session" > "/home/${ADMIN_USER}/.xsession"
    chmod +x "/home/${ADMIN_USER}/.xsession"
    chown "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/.xsession"
    _log_ok ".xsession creat (xfce4-session)"

    mkdir -p "/home/${ADMIN_USER}/ansible-workspace"
    chown -R "${ADMIN_USER}:${ADMIN_USER}" "/home/${ADMIN_USER}/ansible-workspace" 2>/dev/null || true
    _log_ok "ansible-workspace pregătit"
else
    _log_warn "/home/${ADMIN_USER} nu există — .xsession sărit"
fi

systemctl restart xrdp 2>/dev/null \
    && _log_ok "xrdp restartat" \
    || _log_warn "xrdp restart sărit (poate nu e instalat)"

# =============================================================================
# STEP 4: Verifica servicii
# =============================================================================

echo ""
_log_step "[4/4] Verificare servicii..."
systemctl is-active ssh  2>/dev/null && _log_ok "ssh  activ" || _log_warn "ssh  nu este activ"
systemctl is-active xrdp 2>/dev/null && _log_ok "xrdp activ" || _log_warn "xrdp nu este activ"

# ── Rezumat final ────────────────────────────────────────────
_DUR=$(( $(date +%s) - _TS ))
echo ""
_STATUS_CLR=$([ "$_FAIL" -gt 0 ] && echo "$_C_RED" || ([ "$_WARN" -gt 0 ] && echo "$_C_YELLOW" || echo "$_C_GREEN"))
echo -e "${_STATUS_CLR}${_C_BOLD}  ${_SEP}${_C_RST}"
[ "$_FAIL" -gt 0 ] \
    && echo -e "${_C_RED}${_C_BOLD}  FINALIZARE CU ERORI (${ERRORS} erori critice)${_C_RST}" \
    || echo -e "${_C_GREEN}${_C_BOLD}  JUMPHOST FINALIZAT CU SUCCES${_C_RST}"
echo -e "  Durată : $((_DUR/60))m $((_DUR%60))s   |   OK: $_OK   FAIL: $_FAIL   WARN: $_WARN"
echo -e "${_C_GRAY}  Log: ${LOGFILE}${_C_RST}"
echo -e "${_STATUS_CLR}${_C_BOLD}  ${_SEP}${_C_RST}"
echo ""

# Întotdeauna exit 0 — CSE trebuie să raporteze success către Azure
# chiar dacă unele operații au eșuat intern (logate mai sus).
exit 0
