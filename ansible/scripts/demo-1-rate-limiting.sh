#!/usr/bin/env bash
# ============================================================
# demo-1-rate-limiting.sh
# Demonstrates nginx rate limiting — before/after with diff
#
# Usage (from ~/ansible/):
#   chmod +x scripts/demo-1-rate-limiting.sh
#   ./scripts/demo-1-rate-limiting.sh
# ============================================================

set -euo pipefail

DOMAIN="mediasrl.swedencentral.cloudapp.azure.com"
ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs/security-demos"
BEFORE_FILE="${DEMO_DIR}/rate-limit-before.txt"
AFTER_FILE="${DEMO_DIR}/rate-limit-after.txt"

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

test_rate_limit() {
    local label="$1"
    local output_file="$2"
    local endpoint="https://${DOMAIN}/wp-login.php"

    echo "  Endpoint: $endpoint" | tee "$output_file"
    echo "  Sending 12 requests (rate limit: 5/min, burst=3)" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    local blocked=0
    local allowed=0
    for i in $(seq 1 12); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 8 \
            "$endpoint" 2>/dev/null || echo "000")

        if [[ "$CODE" == "429" ]]; then
            echo -e "  Request ${i}:  ${RED}${CODE} Too Many Requests  ← BLOCKED${NC}" | tee -a "$output_file"
            ((blocked++)) || true
        elif [[ "$CODE" =~ ^(200|301|302)$ ]]; then
            echo -e "  Request ${i}:  ${GREEN}${CODE} OK/Redirect${NC}" | tee -a "$output_file"
            ((allowed++)) || true
        else
            echo -e "  Request ${i}:  ${YELLOW}${CODE}${NC}" | tee -a "$output_file"
        fi
        sleep 0.3
    done
    echo "" | tee -a "$output_file"
    echo "  SUMMARY [$label]: $allowed allowed, $blocked blocked" | tee -a "$output_file"
}

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No rate limiting"
warn "All 12 requests will succeed (no protection against brute force)"
echo ""
test_rate_limit "BEFORE" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Applying nginx rate limiting via Ansible"
log "Running: ansible-playbook playbooks/5-harden-security.yml --tags rate_limiting"
echo ""

ansible-playbook playbooks/5-harden-security.yml \
    --tags rate_limiting \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "Rate limiting applied. Waiting 5s for nginx reload..."
sleep 5

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: Rate limiting active"
log "After the burst (3 requests), subsequent requests are blocked with 429"
echo ""
test_rate_limit "AFTER" "$AFTER_FILE"

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — nginx Rate Limiting                 ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Logs saved:"
echo -e "    Before: ${BEFORE_FILE}"
echo -e "    After:  ${AFTER_FILE}"
echo ""
echo -e "  To verify on server:"
echo -e "    nginx -T | grep limit_req"
echo -e "    cat /etc/nginx/conf.d/rate-limiting.conf"
