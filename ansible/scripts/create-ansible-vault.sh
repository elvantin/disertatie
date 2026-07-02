#!/bin/bash
# ============================================================
# create-ansible-vault.sh — SC MEDIA SRL
#
# Runs on the jumphost (vm-jmp-01) via Managed Identity.
# Fetches secrets from kv-mediasrl-persistent and creates
# an AES-256 encrypted group_vars/all/vault.yml.
#
# Usage (from ansible/ directory on jumphost):
#   bash scripts/create-ansible-vault.sh
#
# Prerequisites:
#   - VM Managed Identity with Key Vault Secrets User role on kv-mediasrl-persistent
#   - ansible-vault available (pre-installed in Packer image)
#   - az CLI available (pre-installed in Packer image)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(dirname "$SCRIPT_DIR")"
VAULT_FILE="$ANSIBLE_DIR/group_vars/all/vault.yml"
VAULT_PASS_FILE="$HOME/.vault-pass"
KV_NAME="kv-mediasrl-persistent"

_ok()   { echo "  [OK]  $1"; }
_fail() { echo "  [!!]  $1" >&2; }
_step() { echo "  [>>]  $1"; }

echo ""
echo "  ======================================================"
echo "  SC MEDIA SRL — Ansible Vault Bootstrap"
echo "  Host: $(hostname)  |  $(date '+%Y-%m-%d %H:%M:%S')"
echo "  KV  : $KV_NAME"
echo "  ======================================================"
echo ""

# ── STEP 1: Azure MSI auth ─────────────────────────────────

_step "[1/4] Autentificare Azure via Managed Identity..."
if ! az login --identity --output none 2>/dev/null; then
    _fail "MSI auth esuat. Verificati ca vm-jmp-01 are System-Assigned MSI activat."
    exit 1
fi
_ok "Autentificat via Managed Identity"

# ── STEP 2: Vault password ─────────────────────────────────

_step "[2/4] Preia ansible-vault-password din $KV_NAME..."
VAULT_PASS=$(az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "ansible-vault-password" \
    --query value -o tsv 2>/dev/null) || true

if [ -z "$VAULT_PASS" ]; then
    _fail "Nu s-a putut citi ansible-vault-password din $KV_NAME."
    _fail "Verificati: MSI are rolul 'Key Vault Secrets User' pe $KV_NAME"
    exit 1
fi

printf '%s' "$VAULT_PASS" > "$VAULT_PASS_FILE"
chmod 600 "$VAULT_PASS_FILE"
_ok "Vault password salvat: $VAULT_PASS_FILE (chmod 600)"

# ── STEP 3: Fetch all secrets ──────────────────────────────

_step "[3/4] Preia secrete de infrastructura din $KV_NAME..."

_get() {
    az keyvault secret show \
        --vault-name "$KV_NAME" \
        --name "$1" \
        --query value -o tsv 2>/dev/null || true
}

VM_ADMIN_PASS=$(_get "vm-admin-password")
MYSQL_ROOT_PASS=$(_get "mysql-root-password")
MYSQL_WP_PASS=$(_get "mysql-wordpress-password")
MYSQL_MON_PASS=$(_get "mysql-monitoring-password")
MYSQL_API_PASS=$(_get "mysql-api-password")
WP_ADMIN_PASS=$(_get "wordpress-admin-password")
BACKUP_ENC_KEY=$(_get "mysql-backup-encryption-key")

_errors=0
for _var in VM_ADMIN_PASS MYSQL_ROOT_PASS MYSQL_WP_PASS MYSQL_MON_PASS MYSQL_API_PASS WP_ADMIN_PASS BACKUP_ENC_KEY; do
    if [ -z "${!_var}" ]; then
        _fail "Secret gol sau lipsa: $_var"
        _errors=$((_errors + 1))
    fi
done
if [ $_errors -gt 0 ]; then
    _fail "$_errors secret(e) nu au putut fi preluate. Rulati mai intai 0-bootstrap-keyvault.ps1."
    exit 1
fi
_ok "7/7 secrete preluate din Key Vault"

# ── STEP 4: Create encrypted vault.yml ────────────────────

_step "[4/4] Creare group_vars/all/vault.yml (AES-256)..."
mkdir -p "$(dirname "$VAULT_FILE")"

# Pasam parola direct prin --vault-id cu ID "mediasrl" (diferit de "default").
# Evita conflictul "vault-ids default,default" cu vault_password_file din ansible.cfg.
# ansible-playbook decripteaza corect: incearca TOATE parolele disponibile,
# indiferent de vault-id label — acelasi $VAULT_PASS_FILE este configurat in ansible.cfg.

# Write plaintext to stdin, encrypt directly to file — no plaintext on disk
printf '%s\n' \
    "---" \
    "vault_admin_password: \"$VM_ADMIN_PASS\"" \
    "vault_mysql_root_password: \"$MYSQL_ROOT_PASS\"" \
    "vault_mysql_wordpress_password: \"$MYSQL_WP_PASS\"" \
    "vault_mysql_monitoring_password: \"$MYSQL_MON_PASS\"" \
    "vault_mysql_api_password: \"$MYSQL_API_PASS\"" \
    "vault_wordpress_admin_password: \"$WP_ADMIN_PASS\"" \
    "vault_backup_encryption_key: \"$BACKUP_ENC_KEY\"" \
    | ansible-vault encrypt \
        --vault-id "mediasrl@$VAULT_PASS_FILE" \
        --encrypt-vault-id mediasrl \
        --output "$VAULT_FILE" -

chmod 600 "$VAULT_FILE"

# Quick sanity check — decrypt and discard output
if ! ansible-vault view --vault-id "mediasrl@$VAULT_PASS_FILE" "$VAULT_FILE" > /dev/null 2>&1; then
    _fail "Verificare vault esuat — fisierul poate fi corupt"
    exit 1
fi

_ok "Vault creat si verificat: $VAULT_FILE (AES-256)"

echo ""
echo "  ======================================================"
echo "  Ansible Vault configurat cu succes!"
echo ""
echo "  Vault   : $VAULT_FILE"
echo "  Pass    : $VAULT_PASS_FILE"
echo ""
echo "  Teste rapide:"
echo "    ansible linux   -m ping"
echo "    ansible windows -m win_ping"
echo "  ======================================================"
echo ""
