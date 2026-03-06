#!/usr/bin/env bash
# =============================================================================
# run-playbook.sh — Ansible playbook wrapper with timestamped execution logs
#
# Usage:
#   ./scripts/run-playbook.sh <playbook> [ansible-playbook options...]
#
# Examples:
#   ./run-playbook.sh playbooks/1-setup-ssh-keys.yml --ask-pass
#   ./run-playbook.sh playbooks/2-site.yml
#   ./run-playbook.sh playbooks/2-site.yml --tags nginx,wordpress
#   ./run-playbook.sh playbooks/2-site.yml --limit vm-web-01 -v
#   ./run-playbook.sh playbooks/3-verify.yml
#   ./run-playbook.sh playbooks/4-harden-nginx-ssl.yml
#
# Logs are saved to: logs/YYYY-MM-DD_HH-MM-SS_<playbook>.log
# List recent logs:  ls -lt logs/*.log | head -20
# View last log:     cat $(ls -t logs/*.log | head -1)
# =============================================================================

set -euo pipefail

# ── Arguments ─────────────────────────────────────────────────────────────────
PLAYBOOK="${1:-playbooks/2-site.yml}"
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
# Log file without ANSI color codes (clean, readable in editors)
LOG_FILE_CLEAN="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.clean.log"

# ── Force colors even when stdout is piped (Ansible picks this up) ────────────
export ANSIBLE_FORCE_COLOR=1

# ── Record start time for wall-clock duration ─────────────────────────────────
START_SECONDS="${SECONDS}"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# ── strip_ansi: remove ANSI escape sequences from a string ───────────────────
strip_ansi() { sed 's/\x1b\[[0-9;]*[mGKHF]//g; s/\x1b\[[0-9;]*[ABCD]//g'; }

# ── Header (written to both colored log and clean log) ────────────────────────
HEADER=$(cat <<EOF
================================================================
  ANSIBLE EXECUTION LOG
================================================================
  Playbook  : ${PLAYBOOK}
  Started   : ${START_TIME}
  User      : $(whoami)@$(hostname)
  Directory : ${ANSIBLE_DIR}
  Extra args: ${*:-(none)}
================================================================

EOF
)
echo "${HEADER}" | tee "${LOG_FILE}" | tee >(strip_ansi >> "${LOG_FILE_CLEAN}") > /dev/null
echo "${HEADER}"   # print to terminal (without double-piping issues)

# ── Run playbook — terminal sees colors, both log files capture output ────────
ansible-playbook "${PLAYBOOK}" "$@" 2>&1 \
    | tee >(strip_ansi >> "${LOG_FILE_CLEAN}") \
    | tee -a "${LOG_FILE}"
EXIT_CODE="${PIPESTATUS[0]}"

# ── Calculate wall-clock duration ─────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_SECONDS ))
DURATION_HOURS=$(( ELAPSED / 3600 ))
DURATION_MINS=$(( (ELAPSED % 3600) / 60 ))
DURATION_SECS=$(( ELAPSED % 60 ))
if [ "${DURATION_HOURS}" -gt 0 ]; then
    DURATION_STR="${DURATION_HOURS}h ${DURATION_MINS}m ${DURATION_SECS}s"
elif [ "${DURATION_MINS}" -gt 0 ]; then
    DURATION_STR="${DURATION_MINS}m ${DURATION_SECS}s"
else
    DURATION_STR="${DURATION_SECS}s"
fi

# ── Footer ────────────────────────────────────────────────────────────────────
if [ "${EXIT_CODE}" -eq 0 ]; then
    STATUS_LINE="  Status    : SUCCESS ✓"
else
    STATUS_LINE="  Status    : FAILED  ✗  (exit code: ${EXIT_CODE})"
fi

FOOTER=$(cat <<EOF

================================================================
  EXECUTION SUMMARY
================================================================
  Started   : ${START_TIME}
  Finished  : $(date '+%Y-%m-%d %H:%M:%S %Z')
  Duration  : ${DURATION_STR}
${STATUS_LINE}
  Log (ANSI): ${LOG_FILE}
  Log (text): ${LOG_FILE_CLEAN}
================================================================
EOF
)
echo "${FOOTER}" | tee -a "${LOG_FILE}" | tee -a "${LOG_FILE_CLEAN}" > /dev/null
echo "${FOOTER}"

exit "${EXIT_CODE}"
