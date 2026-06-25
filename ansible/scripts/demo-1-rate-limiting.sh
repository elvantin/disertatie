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
DEMO_DIR="${ANSIBLE_DIR}/logs"
BEFORE_FILE="${DEMO_DIR}/rate-limit-before.txt"
AFTER_FILE="${DEMO_DIR}/rate-limit-after.txt"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-1-rate-limiting-${TIMESTAMP}.html"
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

test_rate_limit() {
    local label="$1"
    local output_file="$2"
    local endpoint="https://${DOMAIN}/wp-login.php"

    {
        echo "  Endpoint: ${endpoint}"
        echo "  $ curl -s -o /dev/null -w \"%{http_code}\" \"${endpoint}\""
        echo "  (12 requests rapid-fire, ~0.3s apart — limit: 5 req/min, burst=3)"
        echo ""

        local blocked=0
        local allowed=0
        for i in $(seq 1 12); do
            TMP_HDR=$(mktemp)
            CODE=$(curl -sk --max-time 8 \
                -D "${TMP_HDR}" -o /dev/null \
                -w "%{http_code}" "${endpoint}" 2>/dev/null || echo "000")
            STATUS_LINE=$(grep "^HTTP/" "${TMP_HDR}" | tail -1 | tr -d '\r' || true)
            RETRY_AFTER=$(grep -i "^Retry-After:" "${TMP_HDR}" | tail -1 | tr -d '\r' || true)
            rm -f "${TMP_HDR}"

            if [[ "$CODE" == "429" ]]; then
                echo -e "  [req ${i}/12]  ${RED}HTTP 429 Too Many Requests  ← BLOCKED${NC}"
                [[ -n "${RETRY_AFTER}" ]] && echo "              ${RETRY_AFTER}"
                ((blocked++)) || true
            elif [[ "$CODE" =~ ^(200|301|302)$ ]]; then
                echo -e "  [req ${i}/12]  ${GREEN}${STATUS_LINE:-HTTP ${CODE} OK}${NC}"
                ((allowed++)) || true
            else
                echo -e "  [req ${i}/12]  ${YELLOW}HTTP ${CODE}${NC}"
            fi
            sleep 0.3
        done
        echo ""
        echo "  SUMMARY [${label}]: ${allowed} allowed, ${blocked} blocked"
    } | tee "${output_file}"
}

# ── RESET ─────────────────────────────────────────────────────────────────────
# Remove rate-limiting config from any previous demo run so BEFORE state is clean

banner "STEP 0 — RESET: Ensuring no rate limiting is active (clean BEFORE state)"
log "Removing rate-limiting nginx conf if present from a previous run..."
ansible vm-web-01 -m shell \
    -a "rm -f /etc/nginx/conf.d/rate-limiting.conf /etc/nginx/snippets/rate-limiting-map.conf; nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null; echo 'nginx reset ok'" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|PLAY\|TASK\|RECAP\|changed\|ok=" || true
sleep 3

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No rate limiting — all 12 requests pass"
warn "Without rate limiting all 12 requests return 200/30x — no brute-force protection"
echo ""
test_rate_limit "BEFORE" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Applying nginx rate limiting via Ansible"
log "Running: ansible-playbook playbooks/harden-security.yml --tags rate_limiting"
echo ""

PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags rate_limiting \
    2>&1 | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

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
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "nginx Rate Limiting" \
    --subtitle     "Brute-force /wp-login.php blocat după burst — 429 Too Many Requests" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — Fără rate limiting: toate cele 12 cereri trec (200 OK / 30x Redirect)" \
    --after-label  "AFTER — Rate limiting activ: primele 2-3 trec (burst), restul → 429 Too Many Requests" \
    --target       "${DOMAIN}" \
    --demo-num     1 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
