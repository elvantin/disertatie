#!/usr/bin/env bash
# =============================================================================
# run-playbook.sh — Ansible playbook wrapper with timestamped execution logs
#
# Usage:
#   ./scripts/run-playbook.sh <playbook> [ansible-playbook options...]
#
# Examples:
#   ./scripts/run-playbook.sh playbooks/site.yml
#   ./scripts/run-playbook.sh playbooks/site.yml --tags nginx,wordpress
#   ./scripts/run-playbook.sh playbooks/site.yml --limit vm-web-01 -v
#   ./scripts/run-playbook.sh playbooks/setup-ssh-keys.yml
#
# Logs are saved to: logs/YYYY-MM-DD_HH-MM-SS_<playbook>.log
# List recent logs:  ls -lt logs/*.log | head -20
# View last log:     cat $(ls -t logs/*.log | head -1)
# =============================================================================

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
PLAYBOOK="${1:-playbooks/site.yml}"
shift || true   # remaining args passed through to ansible-playbook

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOGS_DIR="${ANSIBLE_DIR}/logs"
mkdir -p "${LOGS_DIR}"

# ── Log file name: timestamp + playbook name ──────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
PLAYBOOK_NAME="$(basename "${PLAYBOOK}" .yml)"
LOG_FILE="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.log"

# ── Helper: write to both terminal and log file ───────────────────────────────
log() { echo "$*" | tee -a "${LOG_FILE}"; }

# ── Header ────────────────────────────────────────────────────────────────────
{
echo "================================================================"
echo "  ANSIBLE EXECUTION LOG"
echo "================================================================"
echo "  Playbook  : ${PLAYBOOK}"
echo "  Started   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "  User      : $(whoami)@$(hostname)"
echo "  Directory : ${ANSIBLE_DIR}"
echo "  Extra args: ${*:-(none)}"
echo "================================================================"
echo ""
} | tee "${LOG_FILE}"

# ── Run playbook (capture both stdout and stderr) ─────────────────────────────
ansible-playbook "${PLAYBOOK}" "$@" 2>&1 | tee -a "${LOG_FILE}"
EXIT_CODE="${PIPESTATUS[0]}"

# ── Footer ────────────────────────────────────────────────────────────────────
{
echo ""
echo "================================================================"
echo "  EXECUTION SUMMARY"
echo "================================================================"
echo "  Finished  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
if [ "${EXIT_CODE}" -eq 0 ]; then
    echo "  Status    : SUCCESS ✓"
else
    echo "  Status    : FAILED  ✗  (exit code: ${EXIT_CODE})"
fi
echo "  Log saved : ${LOG_FILE}"
echo "================================================================"
} | tee -a "${LOG_FILE}"

exit "${EXIT_CODE}"
