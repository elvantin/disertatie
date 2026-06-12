#!/usr/bin/env bash
# ============================================================
# demo-5-mysql-hardening.sh
# Demonstrates MySQL hardening + TDE (Transparent Data Encryption)
#
# Before: anonymous users, test DB, unencrypted tablespaces
# After:  secure config + InnoDB tablespace encryption
#
# Usage (from ~/ansible/):
#   ./scripts/demo-5-mysql-hardening.sh
# ============================================================

set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="${ANSIBLE_DIR}/logs/security-demos"
BEFORE_FILE="${DEMO_DIR}/mysql-hardening-before.txt"
AFTER_FILE="${DEMO_DIR}/mysql-hardening-after.txt"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
HTML_FILE="${DEMO_DIR}/demo-5-mysql-hardening-${TIMESTAMP}.html"
DEMO_START=$SECONDS

DB_HOST="vm-db-01"
MYSQL_BIN="C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe"
# Fetch MySQL root password from Key Vault via MSI (jumphost must be logged in)
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

# Run MySQL query via Ansible WinRM
mysql_query() {
    local query="$1"
    ansible "${DB_HOST}" \
        -m ansible.windows.win_shell \
        -a "\$r = & '${MYSQL_BIN}' -u root -p'${ROOT_PASS}' -h 127.0.0.1 -P 3306 -e \"${query}\" 2>&1; Write-Output \$r" \
        2>/dev/null | grep -v "^$\|WARNING\|SUCCESS\|CHANGED" || echo "(query failed)"
}

capture_mysql_state() {
    local label="$1"
    local output_file="$2"

    echo "  === MySQL Security State — ${label} ===" | tee "$output_file"
    echo "" | tee -a "$output_file"

    echo "  1. Anonymous users (should be 0 after hardening):" | tee -a "$output_file"
    mysql_query "SELECT User, Host FROM mysql.user WHERE User='';" \
        | sed 's/^/     /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  2. Test database (should not exist after hardening):" | tee -a "$output_file"
    mysql_query "SHOW DATABASES LIKE 'test';" \
        | sed 's/^/     /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  3. Root accounts (should only be localhost after hardening):" | tee -a "$output_file"
    mysql_query "SELECT User, Host FROM mysql.user WHERE User='root';" \
        | sed 's/^/     /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  4. local_infile setting (should be OFF after hardening):" | tee -a "$output_file"
    mysql_query "SHOW GLOBAL VARIABLES LIKE 'local_infile';" \
        | sed 's/^/     /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  5. TDE — InnoDB tablespace encryption status:" | tee -a "$output_file"
    mysql_query "SELECT NAME, ENCRYPTION FROM information_schema.INNODB_TABLESPACES WHERE NAME LIKE 'wordpress_db/%' OR NAME LIKE 'mediasrl_business/%' ORDER BY NAME LIMIT 10;" \
        | sed 's/^/     /' | tee -a "$output_file"

    echo "" | tee -a "$output_file"
    echo "  6. Keyring plugin status:" | tee -a "$output_file"
    mysql_query "SELECT PLUGIN_NAME, PLUGIN_STATUS FROM information_schema.PLUGINS WHERE PLUGIN_NAME LIKE 'keyring%';" \
        | sed 's/^/     /' | tee -a "$output_file"
}

# ── BEFORE ────────────────────────────────────────────────────────────────────

banner "STEP 1 — BEFORE: MySQL default state (no hardening, no TDE)"
warn "Anonymous users, test DB, unencrypted tablespaces (ENCRYPTION=N)"
echo ""
capture_mysql_state "BEFORE" "$BEFORE_FILE"

# Show raw tablespace file for TDE demonstration
banner "STEP 1b — BEFORE: Tablespace data readable on disk (pre-TDE)"
warn "WordPress post content visible as plaintext in .ibd file:"
echo ""
ansible "${DB_HOST}" -m ansible.windows.win_shell \
    -a "
        \$ibdFile = 'C:/ProgramData/MySQL/MySQL Server 8.0/Data/wordpress_db/wp_posts.ibd'
        if (Test-Path \$ibdFile) {
            \$bytes = [System.IO.File]::ReadAllBytes(\$ibdFile)
            \$text = [System.Text.Encoding]::ASCII.GetString(\$bytes)
            \$matches = [regex]::Matches(\$text, '[a-zA-Z]{6,}')
            \$readable = (\$matches | Select-Object -First 20 | ForEach-Object { \$_.Value }) -join ', '
            Write-Output \"Readable strings found in wp_posts.ibd: \$readable\"
        } else {
            Write-Output 'File not found (check MySQL data directory)'
        }
    " 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS\|CHANGED" | tee -a "$BEFORE_FILE" || \
    echo "  (Could not read tablespace file via Ansible)"

# ── APPLY HARDENING ───────────────────────────────────────────────────────────

banner "STEP 2 — Applying MySQL Hardening + TDE via Ansible"
warn "Note: TDE requires MySQL restart — brief downtime expected"
log "Running: ansible-playbook playbooks/5-harden-security.yml --tags mysql_hardening"
echo ""

ansible-playbook playbooks/5-harden-security.yml \
    --tags mysql_hardening \
    2>&1 | grep -E "(TASK|ok|changed|failed|PLAY RECAP|fatal|mysql-hardening|mysql-tde)" | sed 's/^/  /'

echo ""
log "MySQL hardening + TDE applied. Waiting 15s for MySQL restart..."
sleep 15

# ── AFTER ─────────────────────────────────────────────────────────────────────

banner "STEP 3 — AFTER: MySQL hardened + TDE active"
log "Anonymous users removed, test DB deleted, tablespaces encrypted"
echo ""
capture_mysql_state "AFTER" "$AFTER_FILE"

# Show tablespace file is now unreadable
banner "STEP 3b — AFTER: Tablespace data encrypted on disk (post-TDE)"
log "Same .ibd file is now encrypted — no readable plaintext:"
echo ""
ansible "${DB_HOST}" -m ansible.windows.win_shell \
    -a "
        \$ibdFile = 'C:/ProgramData/MySQL/MySQL Server 8.0/Data/wordpress_db/wp_posts.ibd'
        if (Test-Path \$ibdFile) {
            \$bytes = [System.IO.File]::ReadAllBytes(\$ibdFile)
            \$text = [System.Text.Encoding]::ASCII.GetString(\$bytes)
            \$matches = [regex]::Matches(\$text, '[a-zA-Z]{6,}')
            if (\$matches.Count -lt 5) {
                Write-Output 'ENCRYPTED: No readable strings found in wp_posts.ibd (TDE active)'
            } else {
                \$readable = (\$matches | Select-Object -First 10 | ForEach-Object { \$_.Value }) -join ', '
                Write-Output \"WARNING: Some readable strings still found: \$readable\"
            }
        } else {
            Write-Output 'File not found'
        }
    " 2>/dev/null | grep -v "^$\|WARNING\|SUCCESS\|CHANGED" | tee -a "$AFTER_FILE" || \
    echo "  (check: file contents should be binary/encrypted)"

# ── DIFF ──────────────────────────────────────────────────────────────────────

banner "STEP 4 — DIFF: Before vs After"
echo -e "${YELLOW}--- BEFORE${NC}"
echo -e "${GREEN}+++ AFTER${NC}"
echo ""
diff --color=always "$BEFORE_FILE" "$AFTER_FILE" || true

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  DEMO COMPLETE — MySQL Hardening + TDE               ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Verify encryption in MySQL:"
echo -e "    SELECT NAME, ENCRYPTION FROM information_schema.INNODB_TABLESPACES"
echo -e "    WHERE NAME LIKE 'wordpress_db/%';"
echo -e "    # All rows should show ENCRYPTION = Y"
echo ""

# Generate HTML report
DEMO_ELAPSED=$(( SECONDS - DEMO_START ))
python3 "${ANSIBLE_DIR}/scripts/lib/generate-demo-html.py" \
    --title    "MySQL Hardening + TDE (Transparent Data Encryption)" \
    --subtitle "Utilizatori anonimi eliminați, test DB șters, tablespace-uri InnoDB criptate" \
    --before   "${BEFORE_FILE}" \
    --after    "${AFTER_FILE}" \
    --target   "${DB_HOST}" \
    --demo-num 5 \
    --duration "${DEMO_ELAPSED}s" \
    --html     "${HTML_FILE}" || true
echo -e "    HTML Report: ${HTML_FILE}"
