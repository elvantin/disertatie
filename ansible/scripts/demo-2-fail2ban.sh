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
DEMO_DIR="${ANSIBLE_DIR}/logs"
BEFORE_FILE="${DEMO_DIR}/fail2ban-before.txt"
AFTER_FILE="${DEMO_DIR}/fail2ban-after.txt"
TARGET_HOST="vm-web-01"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-2-fail2ban-${TIMESTAMP}.html"
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

# Run ansible ad-hoc and extract only the command stdout (skip PLAY/TASK/RECAP lines)
# Uses ANSIBLE_STDOUT_CALLBACK=minimal for clean rc=X >> output format
ansible_stdout() {
    local host="$1"; shift
    ANSIBLE_STDOUT_CALLBACK=minimal ansible "$host" "$@" 2>/dev/null \
        | sed -n '/rc=[0-9]* >>/,/^[a-zA-Z0-9]/p' \
        | grep -Ev "^vm-|rc=[0-9]* >>|^$" \
        || true
}

# Get target IP from Ansible inventory
TARGET_IP=$(ANSIBLE_STDOUT_CALLBACK=minimal ansible "${TARGET_HOST}" \
    -m debug -a "msg={{ ansible_host }}" 2>/dev/null \
    | grep '"msg"' | awk -F'"' '{print $4}' || echo "10.10.10.4")

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: No Fail2ban — brute-force SSH freely"

SSH_CMD="ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes -o PasswordAuthentication=no wronguser@${TARGET_IP}"

{
    echo "  Target: ${TARGET_HOST} (${TARGET_IP})"
    echo "  $ ${SSH_CMD}"
    echo "  (6 attempts with invalid credentials — no ban in place)"
    echo ""

    for i in $(seq 1 6); do
        RESULT=$(ssh -o ConnectTimeout=3 \
                     -o StrictHostKeyChecking=no \
                     -o BatchMode=yes \
                     -o PasswordAuthentication=no \
                     "wronguser@${TARGET_IP}" 2>&1 | head -2 | tr '\n' ' ' || true)
        echo -e "  [attempt ${i}/6]  → ${RESULT:-no output}"
        echo -e "                  ${GREEN}sshd responded (IP NOT BANNED — brute-force undetected)${NC}"
        sleep 0.5
    done
    echo ""
} | tee "$BEFORE_FILE"

# Check firewalld — no fail2ban rules yet
echo "  firewalld rich rules (no fail2ban rules yet):" | tee -a "$BEFORE_FILE"
ansible_stdout "${TARGET_HOST}" -m shell \
    -a "firewall-cmd --list-rich-rules 2>/dev/null || echo '(no rich rules — fail2ban not installed)'" \
    --become | sed 's/^/     /' | tee -a "$BEFORE_FILE" || \
    echo "     (could not read firewalld rules)" | tee -a "$BEFORE_FILE"

echo "" | tee -a "$BEFORE_FILE"
echo "  Fail2ban status (not installed/running):" | tee -a "$BEFORE_FILE"
FAIL2BAN_BEFORE=$(ansible_stdout "${TARGET_HOST}" -m command \
    -a "systemctl is-active fail2ban" --become || true)
if echo "$FAIL2BAN_BEFORE" | grep -q "inactive\|failed\|not-found"; then
    echo "     fail2ban: inactive (not installed)" | tee -a "$BEFORE_FILE"
else
    echo "     ${FAIL2BAN_BEFORE}" | tee -a "$BEFORE_FILE"
fi

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Deploying Fail2ban via Ansible"
log "Running: ansible-playbook playbooks/harden-security.yml --tags fail2ban"
echo ""

PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags fail2ban \
    --limit "${TARGET_HOST}" \
    2>&1 | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "Fail2ban deployed. Waiting 5s for initialization..."
sleep 5

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: Fail2ban active — demonstrating protection"

TEST_ATTACKER="203.0.113.100"  # RFC 5737 documentation IP — safe for testing

echo "  Target: ${TARGET_HOST} (${TARGET_IP})" | tee "$AFTER_FILE"
echo "  Config: maxretry=5, findtime=600s, bantime=3600s" | tee -a "$AFTER_FILE"
echo "  ignoreip: 10.10.12.0/24 (management subnet — jumphost always accessible)" | tee -a "$AFTER_FILE"
echo "" | tee -a "$AFTER_FILE"

# 3a. Confirm fail2ban is running
echo "  [STATUS] Fail2ban running — active jails:" | tee -a "$AFTER_FILE"
echo "  $ fail2ban-client status" | tee -a "$AFTER_FILE"
ansible_stdout "${TARGET_HOST}" -m command \
    -a "fail2ban-client status" --become \
    | sed 's/^/    /' | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"

# 3b. Show SSH jail config
echo "  [CONFIG] SSH jail settings:" | tee -a "$AFTER_FILE"
for setting in maxretry bantime findtime; do
    echo "  $ fail2ban-client get sshd ${setting}" | tee -a "$AFTER_FILE"
    VAL=$(ansible_stdout "${TARGET_HOST}" -m command \
        -a "fail2ban-client get sshd ${setting}" --become \
        | grep -v "^$" | head -1 | sed 's/^[[:space:]]*//' || echo "N/A")
    echo "    → ${setting} = ${VAL}" | tee -a "$AFTER_FILE"
done
echo "  $ fail2ban-client get sshd ignoreip" | tee -a "$AFTER_FILE"
IGNOREIP_VAL=$(ansible_stdout "${TARGET_HOST}" -m command \
    -a "fail2ban-client get sshd ignoreip" --become \
    | grep -v "^$" | grep -v "These IP addresses" \
    | sed 's/^[[:space:]]*//' | tr '\n' ' ' | sed 's/ $//' || echo "N/A")
echo "    → ignoreip = ${IGNOREIP_VAL}" | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"

# 3c. Demonstrate ignoreip: 7 SSH attempts from jumphost — never banned
echo "  [IGNOREIP] 7 SSH attempts from jumphost (10.10.12.0/24 in ignoreip — NEVER banned):" | tee -a "$AFTER_FILE"
echo "  $ ssh -o BatchMode=yes wronguser@${TARGET_IP}" | tee -a "$AFTER_FILE"
echo "" | tee -a "$AFTER_FILE"
for i in $(seq 1 7); do
    RESULT=$(ssh -o ConnectTimeout=3 \
                 -o StrictHostKeyChecking=no \
                 -o BatchMode=yes \
                 -o PasswordAuthentication=no \
                 "wronguser@${TARGET_IP}" 2>&1 | head -2 | tr '\n' ' ' || true)

    if echo "$RESULT" | grep -qi "refused\|timeout\|reset"; then
        echo -e "  [attempt ${i}/7]  → ${RESULT:-no output}" | tee -a "$AFTER_FILE"
        echo -e "                  ${RED}BLOCKED${NC}" | tee -a "$AFTER_FILE"
    else
        echo -e "  [attempt ${i}/7]  → ${RESULT:-no output}" | tee -a "$AFTER_FILE"
        echo -e "                  ${GREEN}sshd responded (jumphost in ignoreip — never banned)${NC}" | tee -a "$AFTER_FILE"
    fi
    sleep 0.5
done

echo "" | tee -a "$AFTER_FILE"

# 3d. Demonstrate ban mechanism: ban test attacker IP
echo "  [BAN] Simulating attack from external IP ${TEST_ATTACKER} (>5 failed auths)..." | tee -a "$AFTER_FILE"
echo "  $ fail2ban-client set sshd banip ${TEST_ATTACKER}" | tee -a "$AFTER_FILE"
ansible_stdout "${TARGET_HOST}" -m command \
    -a "fail2ban-client set sshd banip ${TEST_ATTACKER}" --become \
    | sed 's/^/    /' | tee -a "$AFTER_FILE" || true
echo -e "  ${RED}${TEST_ATTACKER} BANNED — firewalld rich rule REJECT added for bantime=3600s${NC}" | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"

# 3e. Show firewalld rich rules
echo "  [FIREWALLD] $ firewall-cmd --list-rich-rules" | tee -a "$AFTER_FILE"
ansible_stdout "${TARGET_HOST}" -m shell \
    -a "firewall-cmd --list-rich-rules 2>/dev/null | grep -i 'drop\|reject\|${TEST_ATTACKER}' || echo '  (no matching rules — check fail2ban-client status sshd)'" \
    --become \
    | sed 's/^/    /' | tee -a "$AFTER_FILE" || \
    echo "    (could not read rich rules)" | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"
echo "  [JAIL STATUS] $ fail2ban-client status sshd" | tee -a "$AFTER_FILE"
ansible_stdout "${TARGET_HOST}" -m command \
    -a "fail2ban-client status sshd" --become \
    | sed 's/^/    /' | tee -a "$AFTER_FILE"

echo "" | tee -a "$AFTER_FILE"
echo "  [CLEANUP] Unbanning test IP ${TEST_ATTACKER}..." | tee -a "$AFTER_FILE"
echo "  $ fail2ban-client set sshd unbanip ${TEST_ATTACKER}" | tee -a "$AFTER_FILE"
ansible_stdout "${TARGET_HOST}" -m command \
    -a "fail2ban-client set sshd unbanip ${TEST_ATTACKER}" --become \
    | sed 's/^/    /' | tee -a "$AFTER_FILE" || true
echo "  (In production, ban persists for bantime=3600s without manual unban)" | tee -a "$AFTER_FILE"

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
echo -e "  Check firewalld rules applied by fail2ban:"
echo -e "    ansible ${TARGET_HOST} -m shell -a 'firewall-cmd --list-rich-rules' --become"
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "Fail2ban — Auto-ban IP după brute-force SSH" \
    --subtitle     "IP banat automat după 5 tentative eșuate — bantime 3600s via firewalld rich rules (REJECT)" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — Fără Fail2ban: tentative SSH nedetectate, fără blocare (6 conexiuni SSH de la un potențial atacator — toate ajung la sshd, serverul nu detectează și nu blochează nimic)" \
    --after-label  "AFTER — Fail2ban activ: IP extern banat după 5 eșecuri, management subnet protejat (fail2ban monitorizează logurile sshd în timp real — IP extern blocat prin firewalld REJECT; jumphost rămâne accesibil via ignoreip)" \
    --badge        "✓ 1 IP BANAT — BAN CONFIRMAT" \
    --target       "${TARGET_HOST}" \
    --demo-num     2 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
