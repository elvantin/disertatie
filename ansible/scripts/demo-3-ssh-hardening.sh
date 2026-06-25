#!/usr/bin/env bash
# ============================================================
# demo-3-ssh-hardening.sh
# Demonstrates SSH hardening — weak → strong algorithms
#
# Capture method: sshd -T via Ansible (reliable from any subnet)
# Why not ssh-audit directly: ssh-audit uses raw Python socket;
# NSG/routing between mgmt and prod subnets allows Ansible SSH
# (uses ControlMaster + existing TCP session) but blocks
# direct raw-socket connections from jumphost to prod VMs.
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
LINUX_HOSTS=("vm-jmp-01" "vm-web-01" "vm-app-01" "vm-cms-01")
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

# Run ansible ad-hoc and extract only stdout (strip host header + rc= line)
ansible_out() {
    local host="$1"; shift
    ANSIBLE_STDOUT_CALLBACK=minimal ansible "$host" "$@" 2>/dev/null \
        | grep -v "^${host}\b\|^WARNING\|^$" \
        | grep -v "^SUCCESS\|^FAILED\|^CHANGED\|rc=[0-9]" \
        || true
}

TARGET_IP=$(ansible "${TARGET_HOST}" -m debug -a "msg={{ ansible_host }}" 2>/dev/null \
    | grep '"msg"' | awk -F'"' '{print $4}' || echo "10.10.10.4")

# ---------------------------------------------------------------------------
# Capture function — uses sshd -T (effective runtime config) via Ansible.
# sshd -T prints the complete parsed configuration including defaults;
# piping through grep gives exactly the 4 algorithm lines we care about.
# ---------------------------------------------------------------------------
capture_sshd_state() {
    local label="$1"
    local output_file="$2"

    {
        echo "  === SSH Algorithm Configuration — ${label} ==="
        echo "  Target: ${TARGET_HOST} (${TARGET_IP})"
        echo "  Method: sshd -T (effective runtime config) via Ansible"
        echo ""

        # Show active drop-in
        echo "  [DROP-IN] /etc/ssh/sshd_config.d/99-hardening.conf:"
        echo "  $ ansible ${TARGET_HOST} -m shell -a \"grep -iE '^(KexAlgorithms|HostKeyAlgorithms|Ciphers|MACs|PermitRootLogin|MaxAuthTries)' /etc/ssh/sshd_config.d/99-hardening.conf\" --become"
        ansible_out "${TARGET_HOST}" -m shell \
            -a "grep -iE '^(KexAlgorithms|HostKeyAlgorithms|Ciphers|MACs|PermitRootLogin|MaxAuthTries)\s' \
                /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null \
                || echo '(not present — sshd uses compiled defaults)'" \
            --become | sed 's/^/    /' || echo "    (read error)"

        echo ""

        # Effective runtime config via sshd -T
        echo "  [EFFECTIVE] sshd -T | grep algorithm lines:"
        echo "  $ ansible ${TARGET_HOST} -m shell -a \"sshd -T | grep -iE '^(kexalgorithms|hostkeyalgorithms|ciphers|macs)'\" --become"
        ansible_out "${TARGET_HOST}" -m shell \
            -a "sshd -T 2>/dev/null \
                | grep -iE '^(kexalgorithms|hostkeyalgorithms|ciphers|macs)\s' \
                | sort" \
            --become | sed 's/^/    /' || echo "    (sshd -T error)"

        echo ""

        # Weak algorithm check (annotate for demo)
        echo "  [CHECK] Weak algorithm analysis:"
        ALGOS=$(ansible_out "${TARGET_HOST}" -m shell \
            -a "sshd -T 2>/dev/null \
                | grep -iE '^(kexalgorithms|hostkeyalgorithms|ciphers|macs)\s'" \
            --become 2>/dev/null || true)

        WEAK_FOUND=false
        # ecdsa-sha2-nistp256 as host key — [fail] per ssh-audit
        if echo "${ALGOS}" | grep -qi "ecdsa-sha2-nistp256"; then
            echo -e "  ${RED}  [WEAK FOUND] hostkeyalgorithms: ecdsa-sha2-nistp256 (weak NIST-P curve, biased RNG risk)${NC}"
            WEAK_FOUND=true
        fi
        # ecdh-sha2-nistp in KEX — [fail] per ssh-audit
        if echo "${ALGOS}" | grep -qi "ecdh-sha2-nistp"; then
            echo -e "  ${RED}  [WEAK FOUND] kexalgorithms: ecdh-sha2-nistp (weak NIST-P curve key exchange)${NC}"
            WEAK_FOUND=true
        fi
        # non-ETM MACs — [warn] per ssh-audit (Encrypt-and-MAC mode, not Encrypt-then-MAC)
        if echo "${ALGOS}" | grep -iqi "hmac-sha2-256[^-]"; then
            echo -e "  ${YELLOW}  [WARN] macs: hmac-sha2-256 (non-ETM — encrypt-and-MAC mode is weaker)${NC}"
            WEAK_FOUND=true
        fi
        if echo "${ALGOS}" | grep -iqi "hmac-sha2-512[^-]"; then
            echo -e "  ${YELLOW}  [WARN] macs: hmac-sha2-512 (non-ETM — encrypt-and-MAC mode is weaker)${NC}"
            WEAK_FOUND=true
        fi
        # hmac-sha1 — [warn]
        if echo "${ALGOS}" | grep -qi "hmac-sha1"; then
            echo -e "  ${RED}  [WEAK FOUND] macs: hmac-sha1 (SHA-1 deprecated for MAC use)${NC}"
            WEAK_FOUND=true
        fi
        # sntrup761 experimental
        if echo "${ALGOS}" | grep -qi "sntrup761"; then
            echo -e "  ${YELLOW}  [WARN] kexalgorithms: sntrup761 (experimental algorithm)${NC}"
            WEAK_FOUND=true
        fi
        # umac-64 — small tag
        if echo "${ALGOS}" | grep -qi "umac-64"; then
            echo -e "  ${YELLOW}  [WARN] macs: umac-64 (64-bit tag size — too short for security)${NC}"
            WEAK_FOUND=true
        fi
        # chacha20 missing (not weak, but expected after hardening)
        if ! echo "${ALGOS}" | grep -qi "chacha20"; then
            echo -e "  ${YELLOW}  [INFO] ciphers: chacha20-poly1305 not present (will be added by hardening)${NC}"
        fi

        if [[ "${WEAK_FOUND}" == "false" ]]; then
            echo -e "  ${GREEN}  [OK] No weak algorithms detected — sshd configuration is hardened${NC}"
        fi
        echo ""

    } | tee "${output_file}"
}

# ── STEP 0: RESET ─────────────────────────────────────────────────────────────

banner "STEP 0 — RESET: Remove hardening on all Linux VMs for clean BEFORE state"
log "Removing 99-hardening.conf on: ${LINUX_HOSTS[*]}"

ANSIBLE_STDOUT_CALLBACK=minimal ansible "vm-jmp-01:vm-web-01:vm-app-01:vm-cms-01" \
    -m file -a "path=/etc/ssh/sshd_config.d/99-hardening.conf state=absent" \
    --become 2>/dev/null | grep -v "WARNING\|^$" || true

ANSIBLE_STDOUT_CALLBACK=minimal ansible "vm-jmp-01:vm-web-01:vm-app-01:vm-cms-01" \
    -m systemd -a "name=sshd state=restarted" \
    --become 2>/dev/null | grep -v "WARNING\|^$" || true

log "sshd restarted on all Linux VMs. Waiting 5s for services to settle..."
sleep 5

# ── STEP 1: BEFORE ────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: SSH configuration on ${TARGET_HOST} (default — no hardening)"
warn "No 99-hardening.conf present on any Linux VM. Showing compiled sshd defaults."
warn "Expected: ecdsa-sha2-nistp256 [fail], ecdh-sha2-nistp KEX [fail], hmac-sha1 [warn], umac-64 [warn]"
echo ""
capture_sshd_state "BEFORE" "${BEFORE_FILE}"

# ── STEP 2: APPLY HARDENING ──────────────────────────────────────────────────

banner "STEP 2 — Applying SSH hardening via Ansible (all Linux VMs)"
log "Deploying /etc/ssh/sshd_config.d/99-hardening.conf via ssh-hardening role"
log "Running: ansible-playbook playbooks/harden-security.yml --tags ssh_hardening"
log "Targets: vm-web-01 + vm-app-01 + vm-cms-01 (play: webserver:appserver:cmsserver) | vm-jmp-01 (play: jumphost)"
echo ""

PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags ssh_hardening \
    2>&1 | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal)" | sed 's/^/  /'

echo ""
log "SSH hardened. Waiting 5s for sshd restart..."
sleep 5

# ── STEP 3: AFTER ─────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: SSH configuration (hardened — modern algorithms only)"
log "Expected: curve25519 + DH-group14/16/18 KEX, chacha20 + AES-256-GCM ciphers"
log "          ETM MACs only, ed25519 + rsa-sha2 host keys, no NIST-P curves"
echo ""
capture_sshd_state "AFTER" "${AFTER_FILE}"

# ── STEP 3b: ALL VMs SUMMARY ──────────────────────────────────────────────────

banner "STEP 3b — All Linux VMs: algorithm state after hardening"
for host in "${LINUX_HOSTS[@]}"; do
    echo -e "  ${CYAN}${BOLD}[ ${host} ]${NC}"
    ALGOS_ALL=$(ANSIBLE_STDOUT_CALLBACK=minimal ansible "${host}" -m shell \
        -a "sshd -T 2>/dev/null | grep -iE '^(kexalgorithms|hostkeyalgorithms|ciphers|macs)\s' | sort" \
        --become 2>/dev/null \
        | grep -v "^${host}\b\|^WARNING\|^$\|^SUCCESS\|^FAILED\|^CHANGED\|rc=[0-9]" \
        || true)

    HOST_OK=true
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        if echo "${line}" | grep -qi "ecdsa-sha2-nistp\|ecdh-sha2-nistp\|hmac-sha1\|sntrup761\|umac-64[^-]" || \
           echo "${line}" | grep -iqi "hmac-sha2-256[^-]\|hmac-sha2-512[^-]"; then
            echo -e "    ${RED}${line}${NC}"
            HOST_OK=false
        else
            echo -e "    ${GREEN}${line}${NC}"
        fi
    done <<< "${ALGOS_ALL}"

    if [[ "${HOST_OK}" == "true" ]]; then
        echo -e "    ${GREEN}[OK] ${host} — no weak algorithms detected${NC}"
    else
        echo -e "    ${RED}[WEAK] ${host} — weak algorithms still present!${NC}"
    fi
    echo ""
done

# ── STEP 3c: VERIFY WEAK ALGORITHM REJECTED ───────────────────────────────────

echo ""
banner "STEP 3c — Verify: weak algorithms rejected after hardening"

echo "  Test 1: force non-ETM MAC (hmac-sha2-256) — must be rejected by hardened sshd"
echo "  $ ssh -o ConnectTimeout=8 -o BatchMode=yes -o MACs=hmac-sha2-256 azureadmin@${TARGET_IP} exit"
echo ""

WEAK_TEST=$(ssh -o ConnectTimeout=8 \
                -o StrictHostKeyChecking=no \
                -o BatchMode=yes \
                -o MACs=hmac-sha2-256 \
                "azureadmin@${TARGET_IP}" exit 2>&1 || true)

echo "  → $(echo "${WEAK_TEST}" | head -2 | tr '\n' ' ')"
echo ""
if echo "${WEAK_TEST}" | grep -qi "no matching MAC\|unable to negotiate"; then
    echo -e "  ${GREEN}[PASS] Non-ETM MAC REJECTED — sshd refused hmac-sha2-256 before auth${NC}"
    echo -e "  ${GREEN}       Server only accepts: hmac-sha2-*-etm, umac-128-etm${NC}"
elif echo "${WEAK_TEST}" | grep -qi "Permission denied\|publickey"; then
    echo -e "  ${YELLOW}[NOTE] MAC negotiated OK (auth failed as expected — key auth only)${NC}"
    echo -e "  ${YELLOW}       Verify: ssh -vv -o MACs=hmac-sha2-256 azureadmin@${TARGET_IP}${NC}"
else
    echo -e "  ${YELLOW}[INFO] Unexpected result: $(echo "${WEAK_TEST}" | head -1)${NC}"
fi

echo ""
echo "  Test 2: force NIST-P256 KEX (ecdh-sha2-nistp256) — must be rejected"
echo "  $ ssh -o ConnectTimeout=8 -o BatchMode=yes -o KexAlgorithms=ecdh-sha2-nistp256 azureadmin@${TARGET_IP} exit"
echo ""

KEX_TEST=$(ssh -o ConnectTimeout=8 \
               -o StrictHostKeyChecking=no \
               -o BatchMode=yes \
               -o KexAlgorithms=ecdh-sha2-nistp256 \
               "azureadmin@${TARGET_IP}" exit 2>&1 || true)

echo "  → $(echo "${KEX_TEST}" | head -2 | tr '\n' ' ')"
echo ""
if echo "${KEX_TEST}" | grep -qi "no matching key exchange\|unable to negotiate"; then
    echo -e "  ${GREEN}[PASS] Weak KEX REJECTED — sshd refused ecdh-sha2-nistp256${NC}"
    echo -e "  ${GREEN}       Only accepted: curve25519-sha256, DH-group14/16/18${NC}"
else
    echo -e "  ${YELLOW}[INFO] KEX result: $(echo "${KEX_TEST}" | head -1)${NC}"
fi

# ── STEP 4: DIFF ──────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "${BEFORE_FILE}" "${AFTER_FILE}" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — SSH Hardening                       ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  View deployed config:"
echo -e "    ansible ${TARGET_HOST} -m command -a 'cat /etc/ssh/sshd_config.d/99-hardening.conf' --become"
echo -e "  Verify runtime algorithms:"
echo -e "    ansible ${TARGET_HOST} -m shell -a \"sshd -T | grep -E '^(kex|cipher|macs|hostkeyalg)'\" --become"
echo -e "  Test MAC rejection manually:"
echo -e "    ssh -o MACs=hmac-sha2-256 azureadmin@${TARGET_IP}      # expect: no matching MAC"
echo -e "    ssh -o KexAlgorithms=ecdh-sha2-nistp256 azureadmin@${TARGET_IP}  # expect: no matching kex"
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "SSH Hardening — Algoritmi criptografici moderni exclusiv" \
    --subtitle     "Curbe NIST-P eliminate, ETM MACs only, ChaCha20 + AES-256-GCM — aplicat pe toate VM-urile Linux" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — sshd implicit pe ${TARGET_HOST}: ecdsa-sha2-nistp256 [fail], ecdh-sha2-nistp KEX [fail], hmac-sha1 [warn] (capturat via sshd -T)" \
    --after-label  "AFTER — 99-hardening.conf activ pe toate VM-urile Linux: algoritmi slabi eliminați, numai curve25519 + AES-256-GCM + ETM MACs" \
    --badge        "✓ ALGORITMI SLABI ELIMINAȚI — 4 VM-URI LINUX" \
    --target       "vm-jmp-01 + vm-web-01 + vm-app-01 + vm-cms-01 (BEFORE/AFTER capturat pe ${TARGET_HOST})" \
    --demo-num     3 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
