#!/usr/bin/env bash
# ============================================================
# demo-5-mysql-hardening.sh
# Demonstrates MySQL security hardening + TDE
#
# STEP 0: Reset MySQL to pre-hardening state
# STEP 1-4: MySQL Hardening (anon users, test DB, local_infile, password policy)
# STEP 5-8: MySQL TDE (keyring_file plugin, tablespace encryption)
#
# MySQL 8.0.45 on Windows Server 2022 (vm-db-01)
#
# Usage (from ~/ansible/):
#   ./scripts/demo-5-mysql-hardening.sh
# ============================================================

set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs"
BEFORE_FILE="${DEMO_DIR}/mysql-hardening-before.txt"
AFTER_FILE="${DEMO_DIR}/mysql-hardening-after.txt"
TDE_BEFORE_FILE="${DEMO_DIR}/mysql-tde-before.txt"
TDE_AFTER_FILE="${DEMO_DIR}/mysql-tde-after.txt"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-5-mysql-hardening-${TIMESTAMP}.html"
DEMO_START=$SECONDS

DB_HOST="vm-db-01"
MYSQL_BIN="C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe"
ROOT_PASS="$(az keyvault secret show --vault-name kv-mediasrl-persistent --name mysql-root-password --query value -o tsv)"

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

mysql_query() {
    local query="$1"
    ANSIBLE_STDOUT_CALLBACK=minimal ansible "${DB_HOST}" \
        -m ansible.windows.win_shell \
        -a "\$r = & '${MYSQL_BIN}' -u root -p'${ROOT_PASS}' -h 127.0.0.1 -P 3306 -e \"${query}\" 2>\$null; Write-Output \$r" \
        2>/dev/null \
        | sed -n '/rc=[0-9]* >>/,/^[a-zA-Z0-9]/p' \
        | grep -Ev "^vm-|rc=[0-9]* >>|^$" \
        || echo "     (query returned no results)"
}

capture_mysql_state() {
    local label="$1"
    local output_file="$2"
    local MYSQL_PROMPT="  $ mysql -u root -h 127.0.0.1 -P 3306 -e"

    echo "  === MySQL Security State — ${label} ===" | tee "$output_file"
    echo "" | tee -a "$output_file"

    echo "  1. Anonymous users (should be 0 after hardening):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT User, Host FROM mysql.user WHERE User='';\"" | tee -a "$output_file"
    mysql_query "SELECT User, Host FROM mysql.user WHERE User='';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  2. Test database (should not exist after hardening):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test';\"" | tee -a "$output_file"
    TEST_DB=$(mysql_query "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test';")
    if echo "${TEST_DB}" | grep -qi "test"; then
        echo "    → test database EXISTS" | tee -a "$output_file"
    else
        echo "    → (empty = test database does NOT exist)" | tee -a "$output_file"
    fi

    echo "" | tee -a "$output_file"
    echo "  3. Root accounts (should only be localhost after hardening):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT User, Host FROM mysql.user WHERE User='root';\"" | tee -a "$output_file"
    mysql_query "SELECT User, Host FROM mysql.user WHERE User='root';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  4. local_infile (should be OFF after hardening):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SHOW GLOBAL VARIABLES LIKE 'local_infile';\"" | tee -a "$output_file"
    mysql_query "SHOW GLOBAL VARIABLES LIKE 'local_infile';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  5. Password validation policy:" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SHOW VARIABLES LIKE 'validate_password%';\"" | tee -a "$output_file"
    mysql_query "SHOW VARIABLES LIKE 'validate_password%';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  6. require_secure_transport (should be ON after hardening):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SHOW GLOBAL VARIABLES LIKE 'require_secure_transport';\"" | tee -a "$output_file"
    mysql_query "SHOW GLOBAL VARIABLES LIKE 'require_secure_transport';" \
        | sed 's/^/    /' | tee -a "$output_file"
}

capture_tde_state() {
    local label="$1"
    local output_file="$2"
    local MYSQL_PROMPT="  $ mysql -u root -h 127.0.0.1 -P 3306 -e"

    echo "  === MySQL TDE State — ${label} ===" | tee "$output_file"
    echo "" | tee -a "$output_file"

    echo "  1. keyring_file plugin (ACTIVE = plugin loaded OK):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME='keyring_file';\"" | tee -a "$output_file"
    mysql_query "SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME='keyring_file';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  2. Encrypted tablespaces — wordpress_db:" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT CONCAT(SUM(ENCRYPTION='Y'), '/', COUNT(*), ' tablespaces encrypted') FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE 'wordpress_db/%';\"" | tee -a "$output_file"
    mysql_query "SELECT CONCAT(IFNULL(SUM(ENCRYPTION='Y'),0), '/', COUNT(*), ' tablespaces encrypted') AS status FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE 'wordpress_db/%';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  3. Encrypted tablespaces — mediasrl_business:" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SELECT CONCAT(SUM(ENCRYPTION='Y'), '/', COUNT(*), ' tablespaces encrypted') FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE 'mediasrl_business/%';\"" | tee -a "$output_file"
    mysql_query "SELECT CONCAT(IFNULL(SUM(ENCRYPTION='Y'),0), '/', COUNT(*), ' tablespaces encrypted') AS status FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE 'mediasrl_business/%';" \
        | sed 's/^/    /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  4. default_table_encryption (ON = new tables encrypted by default):" | tee -a "$output_file"
    echo "  ${MYSQL_PROMPT} \"SHOW GLOBAL VARIABLES LIKE 'default_table_encryption';\"" | tee -a "$output_file"
    mysql_query "SHOW GLOBAL VARIABLES LIKE 'default_table_encryption';" \
        | sed 's/^/    /' | tee -a "$output_file"
}

# ── RESET ─────────────────────────────────────────────────────────────────────
# Re-add anonymous user and test DB so BEFORE state looks unhardened

banner "STEP 0 — RESET: Restoring MySQL to pre-hardening state"
log "Re-adding anonymous user, test database, local_infile=ON, validate_password=LOW, root@10.10.% ..."
echo ""

# validate_password: reset to LOW (component must already be installed — done by 2-site.yml)
mysql_query "SET GLOBAL validate_password.policy = 'LOW'; SET GLOBAL validate_password.length = 4; SET GLOBAL validate_password.mixed_case_count = 0; SET GLOBAL validate_password.number_count = 0; SET GLOBAL validate_password.special_char_count = 0;" 2>/dev/null || true

# Anonymous user + test database (may have been removed by hardening)
mysql_query "CREATE USER IF NOT EXISTS ''@'localhost' IDENTIFIED BY '';" 2>/dev/null || true
mysql_query "GRANT ALL ON *.* TO ''@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null || true
mysql_query "CREATE DATABASE IF NOT EXISTS test; GRANT ALL ON test.* TO ''@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null || true

# local_infile
mysql_query "SET GLOBAL local_infile = 1;" 2>/dev/null || true

# Root accounts: restore broad wildcard root@'10.10.%' (hardening narrows to 10.10.12.%)
mysql_query "DROP USER IF EXISTS 'root'@'10.10.12.%'; CREATE USER IF NOT EXISTS 'root'@'10.10.%' IDENTIFIED BY '${ROOT_PASS}'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'10.10.%' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null || true

echo ""
log "Reset complete."

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: MySQL default state (no hardening)"
warn "Anonymous users present, test DB exists, local_infile=ON, no password policy"
echo ""
capture_mysql_state "BEFORE" "$BEFORE_FILE"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Applying MySQL Hardening via Ansible"
log "Running: ansible-playbook playbooks/harden-security.yml --tags mysql_hardening"
echo ""

TMP_PLAYBOOK_LOG=$(mktemp)
set +e
PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags mysql_hardening \
    2>&1 | tee "${TMP_PLAYBOOK_LOG}" \
         | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal|mysql-hardening)" \
         | sed 's/^/  /'
PLAYBOOK_RC=${PIPESTATUS[0]}
set -e

if [[ "${PLAYBOOK_RC}" -ne 0 ]]; then
    echo ""
    warn "Playbook failed (rc=${PLAYBOOK_RC}) — last 60 lines:"
    echo ""
    tail -60 "${TMP_PLAYBOOK_LOG}" | sed 's/^/  /' || true
    rm -f "${TMP_PLAYBOOK_LOG}"
    exit 1
fi
rm -f "${TMP_PLAYBOOK_LOG}"

echo ""
log "MySQL hardening applied."

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: MySQL hardened"
log "Anonymous users removed, test DB deleted, secure configuration applied"
echo ""
capture_mysql_state "AFTER" "$AFTER_FILE"

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

# ── TDE BEFORE ────────────────────────────────────────────────────────────────

banner "STEP 5 — TDE BEFORE: Tablespace encryption state (pre-TDE)"
warn "keyring_file plugin not loaded, tablespaces ENCRYPTION=N"
echo ""
capture_tde_state "BEFORE" "$TDE_BEFORE_FILE"

# ── APPLY TDE ─────────────────────────────────────────────────────────────────

banner "STEP 6 — Applying MySQL TDE via Ansible"
log "Running: ansible-playbook playbooks/harden-security.yml --tags tde"
echo ""

TMP_TDE_LOG=$(mktemp)
set +e
PYTHONUNBUFFERED=1 ansible-playbook playbooks/harden-security.yml \
    --tags tde \
    2>&1 | tee "${TMP_TDE_LOG}" \
         | grep --line-buffered -E "(TASK|ok|changed|failed|PLAY RECAP|fatal|mysql-tde)" \
         | sed 's/^/  /'
TDE_RC=${PIPESTATUS[0]}
set -e

if [[ "${TDE_RC}" -ne 0 ]]; then
    echo ""
    warn "TDE playbook failed (rc=${TDE_RC}) — last 60 lines:"
    echo ""
    tail -60 "${TMP_TDE_LOG}" | sed 's/^/  /' || true
    rm -f "${TMP_TDE_LOG}"
    exit 1
fi
rm -f "${TMP_TDE_LOG}"

echo ""
log "MySQL TDE applied."

# ── TDE AFTER ─────────────────────────────────────────────────────────────────

banner "STEP 7 — TDE AFTER: Tablespace encryption state (post-TDE)"
log "keyring_file ACTIVE, all InnoDB tablespaces ENCRYPTION=Y"
echo ""
capture_tde_state "AFTER" "$TDE_AFTER_FILE"

# ── TDE DIFF ──────────────────────────────────────────────────────────────────

banner "STEP 8 — DIFF: TDE Before vs After"
echo -e "${YELLOW}--- TDE BEFORE${NC}"
echo -e "${GREEN}+++ TDE AFTER${NC}"
echo ""
diff --color=always "$TDE_BEFORE_FILE" "$TDE_AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — MySQL Hardening + TDE               ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Verificare MySQL Hardening:"
echo -e "    ansible vm-db-01 -m win_shell -a \\"
echo -e "      \"& 'C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe' -u root -p'PASS' -h 127.0.0.1 -P 3306 -e 'SELECT User, Host FROM mysql.user;'\""
echo ""
echo -e "  Verificare TDE:"
echo -e "    ansible vm-db-01 -m win_shell -a \\"
echo -e "      \"& 'C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe' -u root -p'PASS' -h 127.0.0.1 -P 3306 -e 'SELECT NAME, ENCRYPTION FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE \\\"wordpress_db/%\\\";'\""
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title        "MySQL Security Hardening + TDE" \
    --subtitle     "Hardening: anonimi eliminați, test DB șters, local_infile=OFF | TDE: tablespace encryption cu keyring_file" \
    --before       "${BEFORE_FILE}" \
    --after        "${AFTER_FILE}" \
    --before-label "BEFORE — MySQL implicit: utilizatori anonimi, test DB, local_infile=ON, fără politică parole, TDE inactiv" \
    --after-label  "AFTER — MySQL hardened + TDE activ: anonimi eliminați, local_infile=OFF, ENCRYPTION=Y pe toate tablespace-urile" \
    --tde-before   "${TDE_BEFORE_FILE}" \
    --tde-after    "${TDE_AFTER_FILE}" \
    --target       "${DB_HOST}" \
    --demo-num     5 \
    --duration     "${DEMO_ELAPSED}s" \
    --html         "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
