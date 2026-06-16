#!/usr/bin/env bash
# ============================================================
# demo-3-ssh-hardening.sh
# Demonstrates SSH hardening — weak → strong algorithms
# Uses ssh -vv negotiation output for before/after comparison
#
# Usage (from ~/ansible/):
#   ./scripts/demo-3-ssh-hardening.sh
# ============================================================

set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs"
BEFORE_FILE="${DEMO_DIR}/ssh-hardening-before.txt"
AFTER_FILE="${DEMO_DIR}/ssh-hardening-after.txt"
TARGET_HOST="vm-web-01"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-3-ssh-hardening-${TIMESTAMP}.html"
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

TARGET_IP=$(ansible "${TARGET_HOST}" -m debug -a "msg={{ ansible_host }}" 2>/dev/null \
    | grep '"msg"' | awk -F'"' '{print $4}' || echo "10.10.10.4")

capture_ssh_algorithms() {
    local label="$1"
    local output_file="$2"

    echo "  === SSH Algorithm Negotiation — ${label} ===" | tee "$output_file"
    echo "  Target: ${TARGET_HOST} (${TARGET_IP})" | tee -a "$output_file"
    echo "" | tee -a "$output_file"

    # Get server's advertised algorithms via ssh -vv (exit immediately)
    SSH_DEBUG=$(ssh -vv -o ConnectTimeout=5 \
                       -o StrictHostKeyChecking=no \
                       -o BatchMode=yes \
                       "azureadmin@${TARGET_IP}" \
                       exit 2>&1 || true)

    # Extract key lines from negotiation
    echo "  Key Exchange (kex):" | tee -a "$output_file"
    echo "$SSH_DEBUG" | grep -i "kex:" | head -5 | sed 's/^/    /' | tee -a "$output_file" || \
        echo "    (not captured — check manually)" | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  Server host key algorithms:" | tee -a "$output_file"
    echo "$SSH_DEBUG" | grep -i "server_host_key_algorithms\|host key algo" | head -3 | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  Cipher (encryption):" | tee -a "$output_file"
    echo "$SSH_DEBUG" | grep -i "cipher" | grep -v "#" | head -5 | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  MAC:" | tee -a "$output_file"
    echo "$SSH_DEBUG" | grep -i " mac" | grep -v "#" | head -5 | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"

    # Also get sshd_config advertised algorithms from the server
    echo "  Server sshd_config algorithms (from /etc/ssh/sshd_config.d/):" | tee -a "$output_file"
    ansible "${TARGET_HOST}" -m shell \
        -a "cat /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null || echo '(no hardening config — using defaults)'" \
        --become 2>/dev/null \
        | grep -v "^$\|WARNING\|SUCCESS\|CHANGED" | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"

    # Check if weak algorithms are present
    echo "  Weak algorithm check:" | tee -a "$output_file"
    WEAK_FOUND=false
    for weak in "diffie-hellman-group1-sha1" "diffie-hellman-group14-sha1" "hmac-md5" "hmac-sha1" "arcfour"; do
        if echo "$SSH_DEBUG" | grep -qi "$weak"; then
            echo -e "  ${RED}  [WEAK FOUND] $weak${NC}" | tee -a "$output_file"
            WEAK_FOUND=true
        fi
    done
    if [[ "$WEAK_FOUND" == "false" ]]; then
        echo -e "  ${GREEN}  [OK] No weak algorithms detected${NC}" | tee -a "$output_file"
    fi
}

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: Default SSH configuration (may include weak algorithms)"
warn "Default Ubuntu sshd_config may advertise legacy algorithms for compatibility"
echo ""
capture_ssh_algorithms "BEFORE" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Applying SSH hardening via Ansible"
log "Running: ansible-playbook playbooks/5-harden-security.yml --tags ssh_hardening"
echo ""

ansible-playbook playbooks/5-harden-security.yml \
    --tags ssh_hardening \
    --limit "${TARGET_HOST}" \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "SSH hardened. Waiting 5s for sshd restart..."
sleep 5

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: Hardened SSH (only modern algorithms)"
log "Only curve25519, AES-256-GCM, ChaCha20, ETM MACs allowed"
echo ""
capture_ssh_algorithms "AFTER" "$AFTER_FILE"

# Test weak cipher rejection
echo ""
banner "STEP 3b — Verify weak cipher is REJECTED"
echo "  Attempting connection with weak cipher (aes128-cbc)..."
WEAK_TEST=$(ssh -o ConnectTimeout=5 \
                -o StrictHostKeyChecking=no \
                -o BatchMode=yes \
                -o Ciphers=aes128-cbc \
                "azureadmin@${TARGET_IP}" \
                exit 2>&1 || true)
if echo "$WEAK_TEST" | grep -qi "no matching cipher\|unable to negotiate\|refused"; then
    echo -e "  ${GREEN}[PASS] Weak cipher rejected: 'aes128-cbc' not accepted${NC}"
else
    echo -e "  ${YELLOW}[INFO] Result: $WEAK_TEST${NC}"
fi

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — SSH Hardening                       ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Verify with ssh-audit (if installed):"
echo -e "    ssh-audit ${TARGET_IP}"
echo -e "  Or with nmap:"
echo -e "    nmap --script ssh2-enum-algos -p 22 ${TARGET_IP}"
echo -e "  Config deployed to:"
echo -e "    /etc/ssh/sshd_config.d/99-hardening.conf"
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "SSH Hardening — Algoritmi criptografici moderni exclusiv" \
    --subtitle     "curve25519 KEX, ChaCha20/AES-256-GCM cipher, hmac-sha2-512-etm MAC — algoritmi slabi respinși" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — Configurație SSH implicită: posibili algoritmi legacy activi" \
    --after-label  "AFTER — SSH hardening activ: exclusiv algoritmi moderni, slabi respinși explicit" \
    --target       "${TARGET_HOST} (${TARGET_IP})" \
    --demo-num     3 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
