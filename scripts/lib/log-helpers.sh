#!/usr/bin/env bash
# ============================================================
# log-helpers.sh — SC MEDIA SRL — Shared Bash Logging Library
#
# Source this file at the beginning of each bash script:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "$SCRIPT_DIR/lib/log-helpers.sh"
#
# Usage:
#   log_start "Script Title"        # prints banner, opens log file
#   log_header "Section name"
#   log_step   "Doing something..."
#   log_ok     "Resource created"
#   log_warn   "Non-critical issue"
#   log_fail   "Critical error"
#   log_info   "Detail line"
#   log_end                         # prints summary
# ============================================================

# ANSI color codes
_C_CYAN='\033[0;36m'
_C_GREEN='\033[0;32m'
_C_RED='\033[0;31m'
_C_YELLOW='\033[1;33m'
_C_GRAY='\033[0;37m'
_C_BOLD='\033[1m'
_C_DIM='\033[2m'
_C_RST='\033[0m'

# Counters
_LOG_OK=0
_LOG_FAIL=0
_LOG_WARN=0
_LOG_START_TS=0
_LOG_FILE=""
_LOG_TITLE="Script"

LOG_DIR="${LOG_DIR:-${HOME}/logs}"

log_start() {
    _LOG_TITLE="${1:-Script}"
    _LOG_START_TS=$(date +%s)
    _LOG_OK=0; _LOG_FAIL=0; _LOG_WARN=0

    mkdir -p "$LOG_DIR"
    local ts; ts=$(date +"%Y%m%d-%H%M%S")
    local safe; safe=$(echo "$_LOG_TITLE" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    _LOG_FILE="$LOG_DIR/${safe}-${ts}.log"

    # Redirect all output to both terminal and log file
    exec > >(tee -a "$_LOG_FILE") 2>&1

    local now; now=$(date '+%Y-%m-%d %H:%M:%S')
    local sep; sep=$(printf '%.0s=' {1..62})

    echo ""
    echo -e "${_C_CYAN}  ${sep}${_C_RST}"
    printf "${_C_BOLD}  SC MEDIA SRL — %-47s${_C_RST}\n" "$_LOG_TITLE"
    echo -e "${_C_CYAN}  ${sep}${_C_RST}"
    echo -e "${_C_DIM}  Data  : $now${_C_RST}"
    echo -e "${_C_DIM}  Log   : $(basename "$_LOG_FILE")${_C_RST}"
    echo -e "${_C_CYAN}  ${sep}${_C_RST}"
    echo ""
}

log_header() {
    echo ""
    echo -e "  ${_C_CYAN}┌─── $1${_C_RST}"
    echo ""
}

log_step() {
    echo -e "  ${_C_YELLOW}[>>] $*${_C_RST}"
}

log_ok() {
    echo -e "  ${_C_GREEN}[OK] $*${_C_RST}"
    _LOG_OK=$((_LOG_OK + 1))
}

log_warn() {
    echo -e "  ${_C_YELLOW}[!]  $*${_C_RST}"
    _LOG_WARN=$((_LOG_WARN + 1))
}

log_fail() {
    echo -e "  ${_C_RED}[!!] $*${_C_RST}"
    _LOG_FAIL=$((_LOG_FAIL + 1))
}

log_info() {
    echo -e "  ${_C_GRAY}     $*${_C_RST}"
}

log_end() {
    local end_ts; end_ts=$(date +%s)
    local secs=$(( end_ts - _LOG_START_TS ))
    local mins=$(( secs / 60 )); secs=$(( secs % 60 ))
    local sep; sep=$(printf '%.0s=' {1..62})

    echo ""
    if   [ "$_LOG_FAIL" -gt 0 ]; then
        local clr="$_C_RED"
        local status="EXECUȚIE CU ERORI ($_LOG_FAIL erori)"
    elif [ "$_LOG_WARN" -gt 0 ]; then
        local clr="$_C_YELLOW"
        local status="FINALIZAT CU AVERTISMENTE ($_LOG_WARN avertismente)"
    else
        local clr="$_C_GREEN"
        local status="EXECUȚIE REUȘITĂ"
    fi

    echo -e "${clr}${_C_BOLD}  ${sep}${_C_RST}"
    echo -e "${clr}${_C_BOLD}  $status${_C_RST}"
    echo -e "${clr}  Durată : ${mins}m ${secs}s   |   OK: $_LOG_OK   FAIL: $_LOG_FAIL   WARN: $_LOG_WARN${_C_RST}"
    echo -e "${_C_DIM}  Log    : $_LOG_FILE${_C_RST}"
    echo -e "${clr}${_C_BOLD}  ${sep}${_C_RST}"
    echo ""
}
