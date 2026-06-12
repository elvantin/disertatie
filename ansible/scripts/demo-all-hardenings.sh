#!/usr/bin/env bash
# ============================================================
# demo-all-hardenings.sh
# Master demo script — runs all 5 security hardenings
# sequentially with before/after comparison for each.
#
# Usage (from ~/ansible/):
#   chmod +x scripts/demo-all-hardenings.sh
#   ./scripts/demo-all-hardenings.sh
#
#   # Run only specific hardenings:
#   ./scripts/demo-all-hardenings.sh --only 1,3,5
#
#   # Skip confirmation prompts (fully automated):
#   ./scripts/demo-all-hardenings.sh --yes
# ============================================================

set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs/security-demos"
SCRIPTS_DIR="${ANSIBLE_DIR}/scripts"
MASTER_TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
REPORT_FILE="${DEMO_DIR}/security-demo-report-${MASTER_TIMESTAMP}.txt"
HTML_MASTER="${DEMO_DIR}/security-demo-report-${MASTER_TIMESTAMP}.html"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

mkdir -p "$DEMO_DIR"
cd "$ANSIBLE_DIR"

# ── Argument parsing ──────────────────────────────────────────────────────────
AUTO_YES=false
ONLY_STEPS=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)   AUTO_YES=true; shift ;;
        --only)     ONLY_STEPS="$2"; shift 2 ;;
        *)          echo "Usage: $0 [--yes] [--only 1,2,3,4,5]" >&2; exit 1 ;;
    esac
done

should_run() {
    local step="$1"
    [[ -z "$ONLY_STEPS" ]] && return 0
    echo "$ONLY_STEPS" | tr ',' '\n' | grep -q "^${step}$"
}

confirm() {
    local msg="$1"
    if [[ "$AUTO_YES" == "true" ]]; then
        echo -e "${YELLOW}[AUTO] $msg${NC}"
        return 0
    fi
    echo -e "${YELLOW}$msg [Enter to continue / Ctrl+C to abort]${NC}"
    read -r
}

banner() {
    local title="$1"
    local step="$2"
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}${BOLD}║  HARDENING ${step}/5 — ${title}${NC}" | tee -a "$REPORT_FILE"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
}

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}" | tee -a "$REPORT_FILE"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] $*${NC}" | tee -a "$REPORT_FILE"; }

# ── Header ────────────────────────────────────────────────────────────────────
clear
echo "" | tee "$REPORT_FILE"
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║     SC MEDIA SRL — SECURITY HARDENING DEMONSTRATION         ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║     SC IT SECURITY SRL — Infrastructure Security            ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║  Hardenings:                                                ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║    1. nginx Rate Limiting    (vm-web-01)                    ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║    2. Fail2ban               (all Linux VMs)                ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║    3. SSH Hardening          (all Linux VMs)                ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║    4. ModSecurity WAF        (vm-web-01)                    ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║    5. MySQL Hardening + TDE  (vm-db-01)                    ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║  Report: ${REPORT_FILE}${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}║  Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')${NC}" | tee -a "$REPORT_FILE"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

START_TIME=$SECONDS

# ── Hardening 1: Rate Limiting ────────────────────────────────────────────────
if should_run 1; then
    banner "nginx Rate Limiting" "1"
    log "Protects /wp-login.php, /wp-admin/, /xmlrpc.php, /api/ from brute-force"
    confirm "Ready to demo nginx Rate Limiting?"
    bash "${SCRIPTS_DIR}/demo-1-rate-limiting.sh" 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# ── Hardening 2: Fail2ban ─────────────────────────────────────────────────────
if should_run 2; then
    banner "Fail2ban — Automated IP Banning" "2"
    log "Auto-bans IPs after 5 failed SSH/nginx attempts (1-hour ban)"
    confirm "Ready to demo Fail2ban?"
    bash "${SCRIPTS_DIR}/demo-2-fail2ban.sh" 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# ── Hardening 3: SSH Hardening ────────────────────────────────────────────────
if should_run 3; then
    banner "SSH Algorithm Hardening" "3"
    log "Only modern key exchange, ciphers, MACs — weak algorithms removed"
    confirm "Ready to demo SSH Hardening?"
    bash "${SCRIPTS_DIR}/demo-3-ssh-hardening.sh" 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# ── Hardening 4: ModSecurity WAF ─────────────────────────────────────────────
if should_run 4; then
    banner "ModSecurity WAF + OWASP CRS" "4"
    log "SQLi, XSS, path traversal etc. blocked with HTTP 403"
    warn "This step takes ~3 minutes (downloads OWASP CRS)"
    confirm "Ready to demo ModSecurity WAF?"
    bash "${SCRIPTS_DIR}/demo-4-modsecurity.sh" 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# ── Hardening 5: MySQL Hardening + TDE ───────────────────────────────────────
if should_run 5; then
    banner "MySQL Hardening + Transparent Data Encryption" "5"
    log "Removes insecure defaults + encrypts InnoDB tablespaces"
    warn "MySQL will restart — brief downtime on DB"
    confirm "Ready to demo MySQL Hardening + TDE?"
    bash "${SCRIPTS_DIR}/demo-5-mysql-hardening.sh" 2>&1 | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
fi

# ── Final Summary ─────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))
MINS=$(( ELAPSED / 60 ))
SECS=$(( ELAPSED % 60 ))

echo "" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}║     SECURITY HARDENING DEMONSTRATION — COMPLETE             ║${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}║  Duration: ${MINS}m ${SECS}s${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}║  Report:   ${REPORT_FILE}${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}║  Individual demo logs:${NC}" | tee -a "$REPORT_FILE"
for f in "${DEMO_DIR}"/*.txt; do
    [[ -f "$f" ]] && echo -e "${GREEN}${BOLD}║    $(basename "$f")${NC}" | tee -a "$REPORT_FILE"
done
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}" | tee -a "$REPORT_FILE"
echo -e "${GREEN}${BOLD}║  HTML Reports:${NC}" | tee -a "$REPORT_FILE"
for f in "${DEMO_DIR}"/demo-*.html; do
    [[ -f "$f" ]] && echo -e "${GREEN}${BOLD}║    $(basename "$f")${NC}" | tee -a "$REPORT_FILE"
done
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# Generate master HTML report
# NAV format: "num:basename.html" (no spaces in keys — Python looks up label from DEMO_META)
NAV_PAIRS=""
for demo_num in 1 2 3 4 5; do
    html_file=$(ls -t "${DEMO_DIR}/demo-${demo_num}-"*.html 2>/dev/null | head -1 || true)
    if [[ -n "$html_file" ]]; then
        NAV_PAIRS="${NAV_PAIRS} ${demo_num}:$(basename "$html_file")"
    fi
done

python3 "${SCRIPTS_DIR}/lib/generate-demo-html.py" \
    --title    "SC MEDIA SRL — Security Hardening Demonstration" \
    --demo-num ALL \
    --full-log "${REPORT_FILE}" \
    --target   "toate VM-urile Azure (swedencentral)" \
    --duration "${MINS}m ${SECS}s" \
    --nav      "${NAV_PAIRS}" \
    --html     "${HTML_MASTER}" || true

echo ""
echo -e "${GREEN}${BOLD}  Master HTML Report: ${HTML_MASTER}${NC}"
