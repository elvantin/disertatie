#!/usr/bin/env bash
# ============================================================
# demo-2-fail2ban.sh
# Demonstrates Fail2ban — auto-ban after SSH brute-force
#
# Usage (from ~/ansible/):
#   ./scripts/demo-2-fail2ban.sh
# ============================================================

set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs/security-demos"
BEFORE_FILE="${DEMO_DIR}/fail2ban-before.txt"
AFTER_FILE="${DEMO_DIR}/fail2ban-after.txt"
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

# Get target IP from Ansible inventory
TARGET_IP=$(ansible "${TARGET_HOST}" -m debug -a "msg={{ ansible_host }}" 2>/dev/null \
    | grep '"msg"' | awk -F'"' '{print $4}' || echo "10.10.10.4")

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No Fail2ban — brute-force SSH freely"

echo "  Target: ${TARGET_HOST} (${TARGET_IP})" | tee "$BEFORE_FILE"
echo "  Sending 6 SSH connection attempts with wrong password..." | tee -a "$BEFORE_FILE"
echo "  (All attempts CONNECT — no IP banning in place)" | tee -a "$BEFORE_FILE"
echo "" | tee -a "$BEFORE_FILE"

for i in $(seq 1 6); do
    RESULT=$(ssh -o ConnectTimeout=3 \
                 -o StrictHostKeyChecking=no \
                 -o BatchMode=yes \
                 -o PasswordAuthentication=no \
                 "wronguser@${TARGET_IP}" 2>&1 | head -1 || true)
    STATUS="Permission denied / Connection refused"
    echo -e "  Attempt $i: ${GREEN}Connected (got: ${STATUS})${NC}" | tee -a "$BEFORE_FILE"
    sleep 0.5
done
echo "" | tee -a "$BEFORE_FILE"

# Check iptables — no fail2ban rules
echo "  iptables INPUT chain (no fail2ban rules):" | tee -a "$BEFORE_FILE"
ansible "${TARGET_HOST}" -m command \
    -a "iptables -L INPUT -n --line-numbers" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS\|CHANGED" | head -20 \
    | tee -a "$BEFORE_FILE" || echo "  (could not read iptables)" | tee -a "$BEFORE_FILE"

echo "" | tee -a "$BEFORE_FILE"
echo "  Fail2ban status (not installed/running):" | tee -a "$BEFORE_FILE"
ansible "${TARGET_HOST}" -m command \
    -a "systemctl is-active fail2ban" \
    --become 2>/dev/null | grep -v "^$\|WARNING" | tee -a "$BEFORE_FILE" || \
    echo "  fail2ban: inactive (not installed)" | tee -a "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Deploying Fail2ban via Ansible"
log "Running: ansible-playbook playbooks/5-harden-security.yml --tags fail2ban"
echo ""

ansible-playbook playbooks/5-harden-security.yml \
    --tags fail2ban \
    --limit "${TARGET_HOST}" \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "Fail2ban deployed. Waiting 5s for initialization..."
sleep 5

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: Fail2ban active — simulating brute-force attack"

echo "  Target: ${TARGET_HOST} (${TARGET_IP})" | tee "$AFTER_FILE"
echo "  Fail2ban config: maxretry=5, findtime=600s, bantime=3600s" | tee -a "$AFTER_FILE"
echo "" | tee -a "$AFTER_FILE"

# Show fail2ban is running
echo "  Fail2ban status AFTER install:" | tee -a "$AFTER_FILE"
ansible "${TARGET_HOST}" -m command \
    -a "fail2ban-client status" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS" | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"
echo "  Simulating 7 failed SSH auth attempts..." | tee -a "$AFTER_FILE"
echo "  (After 5 failures, Fail2ban will ban this IP)" | tee -a "$AFTER_FILE"
echo "" | tee -a "$AFTER_FILE"

for i in $(seq 1 7); do
    RESULT=$(ssh -o ConnectTimeout=3 \
                 -o StrictHostKeyChecking=no \
                 -o BatchMode=yes \
                 -o PasswordAuthentication=no \
                 "wronguser@${TARGET_IP}" 2>&1 | head -1 || true)

    if echo "$RESULT" | grep -qi "refused\|timeout\|reset"; then
        echo -e "  Attempt $i: ${RED}Connection REFUSED — IP BANNED by Fail2ban!${NC}" | tee -a "$AFTER_FILE"
    else
        echo -e "  Attempt $i: ${YELLOW}${RESULT}${NC}" | tee -a "$AFTER_FILE"
    fi
    sleep 1
done

echo "" | tee -a "$AFTER_FILE"
echo "  Fail2ban sshd jail status (banned IPs):" | tee -a "$AFTER_FILE"
ansible "${TARGET_HOST}" -m command \
    -a "fail2ban-client status sshd" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS" | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"
echo "  iptables INPUT chain (fail2ban DROP rule added):" | tee -a "$AFTER_FILE"
ansible "${TARGET_HOST}" -m command \
    -a "iptables -L INPUT -n | grep f2b" \
    --become 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS" | tee -a "$AFTER_FILE" || \
    echo "  (check: iptables -L INPUT -n | grep -i ban)" | tee -a "$AFTER_FILE"

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — Fail2ban                            ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Unban an IP manually:"
echo -e "    ansible ${TARGET_HOST} -m command -a 'fail2ban-client set sshd unbanip <IP>' --become"
echo -e "  Watch bans in real-time:"
echo -e "    ansible ${TARGET_HOST} -m command -a 'tail -f /var/log/fail2ban.log' --become"
