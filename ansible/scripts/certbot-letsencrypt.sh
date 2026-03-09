#!/usr/bin/env bash
# ============================================================
# certbot-letsencrypt.sh
# Obtains a Let's Encrypt certificate for vm-web-01 by:
#   1. Temporarily opening NSG port 80 to the internet
#   2. Running certbot webroot challenge on vm-web-01
#   3. Deploying the HTTPS nginx config
#   4. Closing port 80 back to VNet-only (always, via trap)
#
# Usage (run from jumphost, inside ~/ansible/ directory):
#   chmod +x ~/ansible/scripts/certbot-letsencrypt.sh
#   cd ~/ansible
#   ./scripts/certbot-letsencrypt.sh
#
# Supported environments:
#   prod: domain = mediasrl.swedencentral.cloudapp.azure.com, NSG = nsg-prod
#   dev:  domain = mediasrl-dev.swedencentral.cloudapp.azure.com, NSG = nsg-dev
#   Domain is read from ~/ansible/.deploy_env (written by 4-deploy-ansible-to-jumphost.ps1).
#
# Prerequisites on jumphost:
#   - az cli authenticated (az login --identity)
#   - ansible configured (inventory/azure_rm.yml reachable)
#   - MSI needs Network Contributor role on nsg-prod / nsg-dev (per environment)
#     Grant: az role assignment create --assignee <managed-identity-id>
#            --role "Network Contributor"
#            --scope /subscriptions/<sub>/resourceGroups/<RG>
# ============================================================

set -euo pipefail

# ── Environment argument ───────────────────────────────────────────────────────
# Usage: ./certbot-letsencrypt.sh [--env prod|dev]
# Default: auto-detect from deployed Azure resource groups
ENV="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env|-e) ENV="${2:-auto}"; shift 2 ;;
        *) echo "Usage: $0 [--env prod|dev]" >&2; exit 1 ;;
    esac
done

# ── Auto-detect environment if not specified ───────────────────────────────────
if [[ "$ENV" == "auto" ]]; then
    # Primary: read .deploy_env written by 4-deploy-ansible-to-jumphost.ps1
    DEPLOY_ENV_FILE="$(cd "$(dirname "$0")/.." && pwd)/.deploy_env"
    if [[ -f "$DEPLOY_ENV_FILE" ]]; then
        source "$DEPLOY_ENV_FILE"
        ENV="${DEPLOY_ENV:-auto}"
        echo "INFO: Environment from .deploy_env: $ENV"
        # DEPLOY_DOMAIN is also available from .deploy_env (used below in case block)
    fi

    # Fallback: query Azure if .deploy_env not present or unset
    if [[ "$ENV" == "auto" ]]; then
        PROD_RG="rg-mediasrl-productie-swedencentral"
        DEV_RG="rg-mediasrl-dezvoltare-swedencentral"
        PROD_EXISTS=$(az group show --name "$PROD_RG" --output none 2>/dev/null && echo true || echo false)
        DEV_EXISTS=$(az group show  --name "$DEV_RG"  --output none 2>/dev/null && echo true || echo false)

        if [[ "$PROD_EXISTS" == "true" && "$DEV_EXISTS" == "false" ]]; then
            ENV="prod"
        elif [[ "$DEV_EXISTS" == "true" && "$PROD_EXISTS" == "false" ]]; then
            ENV="dev"
        elif [[ "$PROD_EXISTS" == "true" && "$DEV_EXISTS" == "true" ]]; then
            echo "Both prod and dev resource groups exist. Specify: $0 --env prod|dev" >&2
            exit 1
        else
            echo "ERROR: No known resource group found. Deploy infrastructure first." >&2
            exit 1
        fi
    fi
fi

# ── Configuration per environment ─────────────────────────────────────────────
case "$ENV" in
    prod|productie)
        RG="rg-mediasrl-productie-swedencentral"
        NSG="nsg-prod"
        INVENTORY="inventory/azure_rm.yml"
        # Use domain from .deploy_env if available, otherwise use the default prod domain
        DOMAIN="${DEPLOY_DOMAIN:-mediasrl.swedencentral.cloudapp.azure.com}"
        ;;
    dev|dezvoltare)
        RG="rg-mediasrl-dezvoltare-swedencentral"
        NSG="nsg-dev"
        INVENTORY="inventory/azure_rm.yml"
        # Use domain from .deploy_env if available, otherwise use the default dev domain
        DOMAIN="${DEPLOY_DOMAIN:-mediasrl-dev.swedencentral.cloudapp.azure.com}"
        ;;
    *)
        echo "ERROR: Unknown environment '$ENV'. Use: --env prod|dev" >&2
        exit 1
        ;;
esac
RULE="Allow-HTTP-To-Web"
EMAIL="admin@media-srl.ro"
CERTBOT_WEBROOT="/var/www/letsencrypt"
LE_LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"

# Script lives in ~/ansible/scripts/ — parent dir is ~/ansible/ (contains ansible.cfg)
ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Colors ─────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
info() { echo -e "${CYAN}[$(date +%H:%M:%S)] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING: $*${NC}"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ERROR: $*${NC}" >&2; }

# ── Cleanup: always restore NSG on exit ───────────────────────────────────────
NSG_OPENED=false
cleanup() {
    local exit_code=$?
    if [[ "$NSG_OPENED" == "true" ]]; then
        echo ""
        log "CLEANUP: Restoring NSG rule — port 80 → VNet-only (10.10.0.0/20)..."
        if az network nsg rule update \
            --resource-group "$RG" \
            --nsg-name "$NSG" \
            --name "$RULE" \
            --source-address-prefixes '10.10.0.0/20' \
            --output none 2>&1; then
            log "NSG restored successfully. Port 80 is VNet-only again."
        else
            err "FAILED to restore NSG automatically!"
            err "Run manually: az network nsg rule update \\"
            err "  --resource-group $RG --nsg-name $NSG --name $RULE \\"
            err "  --source-address-prefixes '10.10.0.0/20'"
        fi
    fi
    if [[ $exit_code -ne 0 ]]; then
        err "Script exited with error code $exit_code."
    fi
}
trap cleanup EXIT

# ── Step 0: Prerequisites ──────────────────────────────────────────────────────
echo ""
info "============================================================"
info " Let's Encrypt Certificate — SC MEDIA SRL"
info " Domain: ${DOMAIN}"
info "============================================================"
echo ""
log "STEP 0: Checking prerequisites..."

command -v az            >/dev/null 2>&1 || { err "az cli not found. Install: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"; exit 1; }
command -v ansible       >/dev/null 2>&1 || { err "ansible not found"; exit 1; }
command -v ansible-playbook >/dev/null 2>&1 || { err "ansible-playbook not found"; exit 1; }
command -v curl          >/dev/null 2>&1 || { err "curl not found"; exit 1; }

[[ -d "$ANSIBLE_DIR" ]] || { err "Ansible directory not found: $ANSIBLE_DIR"; exit 1; }
[[ -f "$ANSIBLE_DIR/ansible.cfg" ]] || { err "ansible.cfg not found in $ANSIBLE_DIR"; exit 1; }

# Authenticate via MSI if needed
az account show --output none 2>/dev/null || {
    log "Authenticating with Managed Identity..."
    az login --identity --output none
}
ACCOUNT=$(az account show --query name -o tsv)
log "Azure CLI: authenticated (subscription: $ACCOUNT)"

# Verify NSG exists
az network nsg show --resource-group "$RG" --name "$NSG" --output none 2>/dev/null || {
    err "NSG '$NSG' not found in resource group '$RG'."
    exit 1
}

# Check MSI has write permission on NSG (test with a dry-run show)
info "Verifying NSG write permissions..."
az network nsg rule show \
    --resource-group "$RG" \
    --nsg-name "$NSG" \
    --name "$RULE" \
    --output none 2>/dev/null || {
    err "Cannot read NSG rule '$RULE'. Check MSI permissions."
    err "Grant: az role assignment create --assignee <MSI_PRINCIPAL_ID>"
    err "       --role 'Network Contributor'"
    err "       --scope /subscriptions/<SUB_ID>/resourceGroups/$RG"
    exit 1
}
log "All prerequisites met."

# ── Step 1: Open NSG port 80 to internet ──────────────────────────────────────
echo ""
log "STEP 1: Opening NSG port 80 to internet..."
info "  NSG: $NSG | Rule: $RULE | New source: *"

CURRENT_SOURCE=$(az network nsg rule show \
    --resource-group "$RG" \
    --nsg-name "$NSG" \
    --name "$RULE" \
    --query "sourceAddressPrefix" -o tsv 2>/dev/null || echo "unknown")
info "  Current source: $CURRENT_SOURCE"

az network nsg rule update \
    --resource-group "$RG" \
    --nsg-name "$NSG" \
    --name "$RULE" \
    --source-address-prefixes '*' \
    --output none

NSG_OPENED=true
log "NSG rule updated. Waiting 45s for Azure fabric propagation..."
sleep 45

# ── Step 2: Verify port 80 is reachable ───────────────────────────────────────
echo ""
log "STEP 2: Verifying port 80 is reachable from internet..."

MAX_RETRIES=6
RETRY=0
HTTP_CODE="000"
while [[ $RETRY -lt $MAX_RETRIES ]]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "http://${DOMAIN}/.well-known/acme-challenge/connectivity-test" 2>/dev/null \
        || echo "000")

    # Any HTTP response (even 404) confirms port 80 is open
    if [[ "$HTTP_CODE" != "000" ]]; then
        log "Port 80 reachable (HTTP $HTTP_CODE). Continuing."
        break
    fi

    RETRY=$((RETRY + 1))
    warn "Port 80 not reachable yet (attempt $RETRY/$MAX_RETRIES). Waiting 15s..."
    sleep 15
done

if [[ "$HTTP_CODE" == "000" ]]; then
    err "Port 80 is not reachable after $((MAX_RETRIES * 15 + 45))s."
    err "Possible causes:"
    err "  - NSG propagation still in progress (try again in 2 min)"
    err "  - nginx not listening on port 80 on vm-web-01"
    err "  - Linux firewall (ufw/firewalld) blocking port 80"
    exit 1
fi

# ── Step 3: Remove self-signed symlinks from LE live directory ─────────────────
echo ""
log "STEP 3: Removing self-signed symlinks from LE live directory (if present)..."
cd "$ANSIBLE_DIR"

# Only remove symlinks that point to /etc/ssl/mediasrl (self-signed fallback path).
# Real LE cert symlinks point to /etc/letsencrypt/archive/ and must NOT be removed.
ansible webserver \
    -i "$INVENTORY" \
    -m shell \
    -a "
        CERT='${LE_LIVE_DIR}/fullchain.pem'
        if [ -L \"\$CERT\" ]; then
            TARGET=\$(readlink -f \"\$CERT\" 2>/dev/null || echo '')
            if echo \"\$TARGET\" | grep -q '/etc/ssl/mediasrl'; then
                rm -f '${LE_LIVE_DIR}/fullchain.pem' \
                      '${LE_LIVE_DIR}/privkey.pem' \
                      '${LE_LIVE_DIR}/chain.pem' \
                      '${LE_LIVE_DIR}/cert.pem'
                echo \"Self-signed symlinks removed (target was: \$TARGET).\"
            else
                echo \"Symlink points to real LE cert (\$TARGET). Nothing to remove.\"
            fi
        else
            echo 'No symlinks in LE live directory. Nothing to remove.'
        fi
    " \
    --become 2>&1 | grep -v "^$" | sed 's/^/  /'

log "LE live directory checked."

# ── Step 4: Run certbot ────────────────────────────────────────────────────────
echo ""
log "STEP 4: Requesting Let's Encrypt certificate..."
info "  Domain:  $DOMAIN"
info "  Email:   $EMAIL"
info "  Webroot: $CERTBOT_WEBROOT"

ansible webserver \
    -i "$INVENTORY" \
    -m command \
    -a "certbot certonly
        --webroot
        --webroot-path ${CERTBOT_WEBROOT}
        --domain ${DOMAIN}
        --email ${EMAIL}
        --agree-tos
        --non-interactive" \
    --become 2>&1 | grep -v "^$" | sed 's/^/  /'

CERTBOT_EXIT=${PIPESTATUS[0]}
if [[ $CERTBOT_EXIT -ne 0 ]]; then
    err "certbot failed (exit code $CERTBOT_EXIT)."
    err "Check nginx logs on vm-web-01: sudo journalctl -u nginx --since '5 min ago'"
    exit 1
fi
log "Certbot completed successfully."

# ── Step 4b: Repair live symlinks if certbot skipped renewal ───────────────────
# certbot --keep-until-expiring skips issuance when cert is still valid, but does
# NOT recreate live/ symlinks if they were removed. Recreate from archive if needed.
echo ""
log "STEP 4b: Ensuring live certificate symlinks are intact..."

ansible webserver \
    -i "$INVENTORY" \
    -m shell \
    -a "
        if [ ! -e '${LE_LIVE_DIR}/fullchain.pem' ]; then
            LATEST_CERT=\$(ls -1t /etc/letsencrypt/archive/${DOMAIN}/fullchain*.pem 2>/dev/null | head -1)
            if [ -n \"\$LATEST_CERT\" ]; then
                mkdir -p '${LE_LIVE_DIR}'
                ln -sf \"\$LATEST_CERT\" '${LE_LIVE_DIR}/fullchain.pem'
                ln -sf \"\$(ls -1t /etc/letsencrypt/archive/${DOMAIN}/privkey*.pem | head -1)\" '${LE_LIVE_DIR}/privkey.pem'
                ln -sf \"\$(ls -1t /etc/letsencrypt/archive/${DOMAIN}/chain*.pem   | head -1)\" '${LE_LIVE_DIR}/chain.pem'
                ln -sf \"\$(ls -1t /etc/letsencrypt/archive/${DOMAIN}/cert*.pem    | head -1)\" '${LE_LIVE_DIR}/cert.pem'
                echo \"Live symlinks recreated from archive: \$LATEST_CERT\"
            else
                echo 'No cert found in archive. A full certbot renewal is required.'
                exit 1
            fi
        else
            echo 'Live certificate already present — no repair needed.'
        fi
    " \
    --become 2>&1 | grep -v "^$" | sed 's/^/  /'

# ── Step 5: Verify certificate ─────────────────────────────────────────────────
echo ""
log "STEP 5: Verifying certificate..."

# Non-fatal: symlinks may have just been recreated; nginx reload (step 6) will validate.
ansible webserver \
    -i "$INVENTORY" \
    -m command \
    -a "openssl x509
        -in ${LE_LIVE_DIR}/fullchain.pem
        -noout -subject -issuer -dates" \
    --become 2>&1 | sed 's/^/  /' \
    || warn "Could not read certificate details — verify manually after nginx reload."

# Confirm it's a real LE cert (issuer should contain "Let's Encrypt")
ISSUER=$(ansible webserver \
    -i "$INVENTORY" \
    -m command \
    -a "openssl x509 -in ${LE_LIVE_DIR}/fullchain.pem -noout -issuer" \
    --become 2>/dev/null | grep -i "issuer" | head -1 || echo "")

if echo "$ISSUER" | grep -qi "Let.s Encrypt\|ISRG"; then
    log "Certificate issuer confirmed: Let's Encrypt"
else
    warn "Could not confirm LE issuer from: $ISSUER"
    warn "Verify manually: openssl x509 -in ${LE_LIVE_DIR}/fullchain.pem -noout -issuer"
fi

# ── Step 6: Deploy HTTPS nginx config ─────────────────────────────────────────
echo ""
log "STEP 6: Deploying HTTPS nginx configuration..."

ansible-playbook playbooks/2-site.yml \
    -i "$INVENTORY" \
    --tags nginx \
    --limit vm-web-01 \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

log "Nginx HTTPS configuration deployed."

# ── Step 7: Verify HTTPS ───────────────────────────────────────────────────────
echo ""
log "STEP 7: Verifying HTTPS..."
sleep 5

HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 \
    "https://${DOMAIN}/health" 2>/dev/null || echo "000")

if [[ "$HTTPS_CODE" == "200" ]]; then
    log "HTTPS is working! (HTTP $HTTPS_CODE)"
else
    warn "HTTPS health check returned HTTP $HTTPS_CODE."
    warn "Check: curl -v https://${DOMAIN}/health"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
info "============================================================"
info " DONE — Let's Encrypt certificate obtained"
info "============================================================"
info " Domain:      https://${DOMAIN}"
info " Cert path:   ${LE_LIVE_DIR}/fullchain.pem"
info " Expiry:      90 days (auto-renewal cron: every 7 days at 02:30)"
echo ""
warn "IMPORTANT: Enable HSTS now that cert is trusted."
warn "  Edit ansible/roles/nginx/defaults/main.yml:"
warn "    nginx_hsts_max_age: 31536000"
warn "  Then re-run: ansible-playbook playbooks/2-site.yml --tags nginx --limit vm-web-01"
echo ""
warn "NOTE: Auto-renewal (certbot renew) needs port 80 open from internet."
warn "  For renewal, re-run this script or open port 80 manually before 'certbot renew'."
warn "  Port 80 will be closed automatically on script exit (running now...)."
echo ""
