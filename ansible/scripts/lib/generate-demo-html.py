#!/usr/bin/env python3
"""
generate-demo-html.py
SC IT SECURITY SRL / SC MEDIA SRL — Disertatie Master 2026

Generates presentation-quality HTML security demo reports.
Called at the end of each demo-N-*.sh script.

Usage:
    python3 generate-demo-html.py \
        --title    "nginx Rate Limiting" \
        --subtitle "Demonstratie brute-force blocat" \
        --before   logs/rate-limit-before.txt \
        --after    logs/rate-limit-after.txt \
        --target   "mediasrl.swedencentral.cloudapp.azure.com" \
        --demo-num 1 \
        --duration "47s" \
        --html     logs/demo-1-rate-limiting-2026-06-13.html

    # Master report (demo-all-hardenings.sh):
    python3 generate-demo-html.py \
        --title    "Security Hardening — Demonstratie completa" \
        --demo-num ALL \
        --full-log logs/security-demo-report-TIMESTAMP.txt \
        --nav      "1:demo-1.html 2:demo-2.html ..." \
        --duration "18m" \
        --html     logs/security-demo-report-TIMESTAMP.html
"""

import argparse
import re
import os
import html as html_mod
from datetime import datetime
import difflib

# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------
ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)


def esc(s: str) -> str:
    return html_mod.escape(strip_ansi(s).rstrip('\n'))


# ---------------------------------------------------------------------------
# Line classification — drives syntax coloring in log blocks
# ---------------------------------------------------------------------------
def classify_line(raw_line: str) -> str:
    s = strip_ansi(raw_line).upper().strip()
    if not s:
        return 'empty'

    if re.search(r'[╔╠╚╗╝║╣]', strip_ansi(raw_line)):
        return 'banner'

    # ssh-audit specific patterns — must be checked before general patterns
    # because [FAIL]/[WARN] are embedded in structured lines like "(kex) ... -- [fail]"
    if re.search(r'\[FAIL\]', s):
        return 'sec-bad'   # bold red — cryptographic failure (weak curve, broken algo)
    if re.search(r'\[INFO\]', s):
        return 'ok'        # green — algorithm passes all checks
    if re.search(r'^\(REC\) -', s):
        return 'sec-bad'   # recommendation: algo to remove (bad, present but should go)
    if re.search(r'^\(REC\) \+', s):
        return 'sec-good'  # recommendation: algo to add (good, missing but should be there)
    if s.startswith('# ') and re.search(r'^# [A-Z]', s):
        return 'sec-hdr'   # ssh-audit section header (# key exchange algorithms, etc.)

    # sshd -T capture section markers
    if re.search(r'^\[DROP-IN\]|\[EFFECTIVE\]|\[CHECK\]', s):
        return 'sec-hdr'

    # sshd -T effective algorithm lines — color based on weak algorithm presence
    if re.search(r'^(KEXALGORITHMS|HOSTKEYALGORITHMS|CIPHERS|MACS)\s', s):
        _weak = [
            r'ECDSA-SHA2-NISTP',          # weak NIST-P host key
            r'ECDH-SHA2-NISTP',           # weak NIST-P key exchange
            r'HMAC-SHA1(?!-ETM)',          # SHA-1 MAC (deprecated)
            r'HMAC-SHA2-256(?!-ETM)',      # non-ETM: encrypt-and-MAC weakness
            r'HMAC-SHA2-512(?!-ETM)',      # non-ETM: encrypt-and-MAC weakness
            r'UMAC-64(?!-ETM)',            # 64-bit tag — too short
            r'SNTRUP761',                  # experimental — not production-safe
            r'AES128-CBC|AES192-CBC|AES256-CBC',  # CBC mode ciphers
            r'ARCFOUR|3DES|BLOWFISH',     # broken stream/block ciphers
        ]
        if any(re.search(p, s) for p in _weak):
            return 'sec-bad'
        return 'ok'

    if re.search(
        r'BLOCKED|429 TOO MANY|IP BANNED|BANNED BY FAIL2BAN|'
        r'CONNECTION REFUSED|CONNECTION.*RESET.*BAN|'
        r'ENCRYPTED: NO READABLE|ENCRYPTION\s*=\s*Y\b|'
        r'\[OK\].*NO WEAK|WEAK CIPHER REJECTED|'
        r'\[PASS\]|\[BLOCKED\s+\d{3}\]|'
        r'ANONYMOUS USERS.*:\s*0|TEST DB.*NOT EXIST',
        s
    ):
        return 'sec-good'

    if re.search(
        r'NOT BLOCKED|← NOT BLOCKED|PASSED \d{3}|'
        r'\[WEAK FOUND\]|ENCRYPTION\s*=\s*N\b|'
        r'WARNING.*READABLE|SOME READABLE',
        s
    ):
        return 'sec-bad'

    if re.search(
        r'\b(OK|PASS|COMPLETE|SUCCESS|ACTIVE|RUNNING|INSTALLED|'
        r'REACHABLE|ALLOW|ENABLED|ALLOW[EE]D)\b', s
    ):
        return 'ok'

    if re.search(r'\b(FAIL|ERROR|FATAL|UNREACHABLE)\b', s):
        return 'fail'

    if re.search(r'\bWARN\b|CAUTION|DEPRECATED|DOWNTIME', s):
        return 'warn'

    if re.search(r'^===\s+|^STEP\s+\d|^SUMMARY\s*[\[\(]|^HARDENING\s+\d', s):
        return 'sec-hdr'

    if re.search(r'(REQUEST|ATTEMPT)\s+\d+\s*:', s):
        return 'item'

    return 'normal'


# ---------------------------------------------------------------------------
# Render log lines to HTML
# ---------------------------------------------------------------------------
def render_lines(lines: list, max_lines: int = 0) -> str:
    if max_lines and len(lines) > max_lines:
        lines = lines[:max_lines]
    out = []
    for line in lines:
        raw = strip_ansi(line).rstrip()
        if not raw:
            out.append('<div class="ll-empty"> </div>')
            continue
        cls = classify_line(line)
        escaped = html_mod.escape(raw)
        out.append(f'<div class="ll {cls}">{escaped}</div>')
    return '\n'.join(out)


# ---------------------------------------------------------------------------
# Unified diff to HTML
# ---------------------------------------------------------------------------
def diff_html(before_lines: list, after_lines: list) -> str:
    b = [strip_ansi(l).rstrip('\n') for l in before_lines]
    a = [strip_ansi(l).rstrip('\n') for l in after_lines]
    diff = list(difflib.unified_diff(b, a, fromfile='BEFORE', tofile='AFTER', lineterm=''))
    if not diff:
        return '<div class="no-diff">ℹ Nu s-au detectat diferențe textuale între BEFORE și AFTER.</div>'
    rows = []
    for line in diff:
        e = html_mod.escape(line)
        if line.startswith('---') or line.startswith('+++'):
            rows.append(f'<div class="df-meta">{e}</div>')
        elif line.startswith('@@'):
            rows.append(f'<div class="df-hunk">{e}</div>')
        elif line.startswith('+'):
            rows.append(f'<div class="df-add">{e}</div>')
        elif line.startswith('-'):
            rows.append(f'<div class="df-del">{e}</div>')
        else:
            rows.append(f'<div class="df-ctx">{e}</div>')
    return '\n'.join(rows)


# ---------------------------------------------------------------------------
# File reader
# ---------------------------------------------------------------------------
def read_file(path: str) -> list:
    if not path or not os.path.isfile(path):
        return []
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as f:
            return f.readlines()
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Statistics extraction
# ---------------------------------------------------------------------------
def count_stats(before_lines: list, after_lines: list) -> dict:
    bt = ''.join(strip_ansi(l) for l in before_lines).upper()
    at = ''.join(strip_ansi(l) for l in after_lines).upper()
    return {
        'blocked_before': len(re.findall(r'BLOCKED|429|BANNED|REFUSED.*BAN', bt)),
        'blocked_after':  len(re.findall(r'BLOCKED|429|BANNED|REFUSED.*BAN', at)),
        'ok_before':      len(re.findall(r'PASSED \d{3}|NOT BLOCKED|200 OK|ALLOW', bt)),
        'ok_after':       len(re.findall(r'PASSED \d{3}|NOT BLOCKED|200 OK|ALLOW', at)),
        'changed':        len(re.findall(r'\bCHANGED\b', at)),
    }


# ---------------------------------------------------------------------------
# Demo metadata (icon + accent colour)
# ---------------------------------------------------------------------------
DEMO_META = {
    '1':    {'icon': '⚡',  'color': '#f0883e', 'label': 'nginx Rate Limiting'},
    '2':    {'icon': '🛡',  'color': '#d29922', 'label': 'Fail2ban'},
    '3':    {'icon': '🔐', 'color': '#79c0ff', 'label': 'SSH Hardening'},
    '4':    {'icon': '🧱', 'color': '#3fb950', 'label': 'ModSecurity WAF'},
    '5':    {'icon': '💾', 'color': '#bc8cff', 'label': 'MySQL Hardening + TDE'},
    'ALL':  {'icon': '🔒', 'color': '#58a6ff', 'label': 'Security Hardening Demo'},
    'CERT': {'icon': '🔏', 'color': '#79c0ff', 'label': "Let's Encrypt TLS"},
}

# ---------------------------------------------------------------------------
# Demo explanations — shown to examination committee in Romanian
# risk_body / prot_body may contain safe inline HTML (<code>, <strong>)
# ---------------------------------------------------------------------------
DEMO_EXPLANATIONS = {
    '1': {
        'risk_title': 'Risc identificat (fără hardening)',
        'risk_body': (
            'Fără rate limiting, un atacator poate lansa un atac <strong>brute-force nelimitat</strong> '
            'asupra <code>/wp-login.php</code>, testând mii de combinații de utilizator/parolă pe minut, '
            'fără nicio penalizare din partea serverului web.'
        ),
        'prot_title': 'Protecție implementată (după hardening)',
        'prot_body': (
            'nginx limitează endpoint-ul la <strong>5 cereri/minut</strong> cu un burst de 3. '
            'Cererile care depășesc limita primesc imediat <strong>HTTP 429 Too Many Requests</strong>, '
            'blocând orice tentativă de brute-force fără a afecta utilizatorii legitimi.'
        ),
        'method': (
            '12 cereri HTTP consecutive la /wp-login.php (interval 0.3s între cereri). '
            'BEFORE: toate trec (200/30x). AFTER: primele 3 (burst) trec, celelalte primesc 429.'
        ),
        'config':   'nginx: limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m  +  limit_req zone=login burst=3 nodelay',
        'standard': 'OWASP Top 10 2021 — A07: Identification and Authentication Failures',
        'conclusion': (
            'Rate limiting-ul nginx protejează eficient formularul de autentificare WordPress împotriva '
            'atacurilor brute-force. Primele 3 cereri din burst sunt permise (comportament normal al '
            'utilizatorilor legitimi), toate cele ulterioare sunt blocate cu <strong>429 Too Many Requests</strong>. '
            'Configurația nu afectează utilizatorii normali și este persistent prin <code>/etc/nginx/conf.d/rate-limiting.conf</code>.'
        ),
    },
    '2': {
        'risk_title': 'Risc identificat (fără hardening)',
        'risk_body': (
            'Fără Fail2ban, atacatorii pot testa <strong>nelimitat</strong> combinații de credențiale SSH '
            'sau HTTP. Un atac brute-force automatizat poate testa zeci de mii de parole pe oră fără '
            'niciun mecanism de detecție sau blocare din partea serverului.'
        ),
        'prot_title': 'Protecție implementată (după hardening)',
        'prot_body': (
            'Fail2ban monitorizează logurile SSH și HTTP în timp real și <strong>blochează automat '
            'via firewalld rich rules</strong> (REJECT icmp-port-unreachable) orice IP care eșuează '
            'autentificarea de <strong>5 ori în 10 minute</strong> (ban de 1 oră). '
            'Subrețeaua de management <code>10.10.12.0/24</code> este în lista '
            '<code>ignoreip</code> — jumphost-ul nu poate fi blocat accidental, '
            'Ansible rămâne funcțional indiferent de câte tentative eșuate vin din subnet-ul de management.'
        ),
        'method': (
            '6 tentative SSH eșuate simulate de la IP-ul extern 203.0.113.100 (RFC 5737 — IP rezervat pentru testare). '
            'BEFORE: nedetectate, toate conexiunile ajung la sshd (nicio regulă fail2ban). '
            'AFTER: IP extern banat automat după 5 eșecuri via firewalld REJECT; '
            '7 tentative de la jumphost (10.10.12.0/24) nu declanșează banul — ignoreip activ.'
        ),
        'config':   'fail2ban: maxretry=5, findtime=600s, bantime=3600s, ignoreip=127.0.0.1/8 ::1 10.10.12.0/24 | banaction=firewallcmd-rich-rules (REJECT)',
        'standard': 'CIS Benchmark SSH Server Configuration + NIST SP 800-53 AC-7 (Unsuccessful Logon Attempts)',
        'conclusion': (
            'Fail2ban detectează și blochează automat atacurile brute-force prin monitorizarea în timp real '
            'a logurilor de autentificare. Subrețeaua de management este exclusă din blocare (<code>ignoreip</code>), '
            'garantând că jumphost-ul (vm-jmp-01) nu poate bloca accidental accesul administrativ Ansible. '
            'Regulile <strong>firewalld rich rules</strong> sunt persistente și se restaurează automat la repornire prin '
            '<code>fail2ban.service</code>. Tipul de blocare este <code>REJECT icmp-port-unreachable</code> '
            '(nu DROP) — clientul primește imediat un răspuns de refuz, fără timeout. '
            'Orice IP banat este vizibil în timp real cu <code>fail2ban-client status sshd</code>.'
        ),
    },
    '3': {
        'risk_title': 'Risc identificat (fără hardening)',
        'risk_body': (
            'Analiza <code>ssh-audit</code> identifică <strong>[fail] ecdsa-sha2-nistp256</strong> '
            'ca algoritm de cheie de host — curba NIST-P256 este considerată slabă din cauza '
            'riscului de RNG biased (backdoor-ul potențial al NIST). '
            'De asemenea, <strong>[warn] hmac-sha2-256</strong> și <strong>hmac-sha2-512</strong> '
            'în mod non-ETM (Encrypt-and-MAC) sunt vulnerabile la atacuri de tip '
            'padding oracle față de varianta ETM (Encrypt-then-MAC). '
            'Toate aceste conexiuni ar putea fi compromise prin atacuri criptanalitice '
            'avansate sau de tip downgrade.'
        ),
        'prot_title': 'Protecție implementată (după hardening)',
        'prot_body': (
            'sshd restricționează algoritmii exclusiv la cei moderni prin '
            '<code>/etc/ssh/sshd_config.d/99-hardening.conf</code>: '
            '<code>curve25519-sha256 + DH-group{14,16,18}-sha{256,512}</code> (KEX), '
            '<code>chacha20-poly1305 + aes256-gcm</code> (cipher AEAD), '
            '<code>hmac-sha2-{512,256}-etm + umac-128-etm</code> (MAC ETM only), '
            '<code>ssh-ed25519 + rsa-sha2-{512,256}</code> (host keys — fără ecdsa). '
            'Conexiunile cu algoritmi slabi sunt <strong>explicit respinse</strong> '
            '("no matching MAC/kex found").'
        ),
        'method': (
            'Captură via <code>sshd -T | grep -iE "^(kexalgorithms|ciphers|macs|hostkeyalgorithms)"</code> '
            'rulat pe server prin Ansible — returnează configurația runtime efectivă inclusiv valorile implicite. '
            'BEFORE: fișierul 99-hardening.conf este absent — sshd include ecdsa-sha2-nistp256 și MACs non-ETM. '
            'AFTER: 99-hardening.conf activ — algoritmii slabi eliminați complet din ofertă. '
            'Test de respingere: ssh cu <code>-o MACs=hmac-sha2-256</code> și '
            '<code>-o KexAlgorithms=ecdh-sha2-nistp256</code> — ambele refuzate cu "unable to negotiate".'
        ),
        'config':   '/etc/ssh/sshd_config.d/99-hardening.conf — KexAlgorithms, Ciphers, MACs, HostKeyAlgorithms, PermitRootLogin no, MaxAuthTries 3, LoginGraceTime 30',
        'standard': 'BSI TR-02102-4 (SSH), NIST SP 800-57, CIS Benchmark Level 2 — SSH Server',
        'conclusion': (
            'SSH Hardening elimină algoritmii clasificați <code>[fail]</code> și <code>[warn]</code> de <code>ssh-audit</code>. '
            'Cheia de host <code>ecdsa-sha2-nistp256</code> (curba NIST-P slabă) este înlocuită cu '
            '<code>ssh-ed25519</code> și <code>rsa-sha2-512</code>. '
            'MAC-urile non-ETM (Encrypt-and-MAC) sunt eliminate — rămân exclusiv variantele '
            '<code>-etm@openssh.com</code> (Encrypt-then-MAC, rezistente la padding oracle). '
            'Configurația plasată în <code>/etc/ssh/sshd_config.d/99-hardening.conf</code> '
            'are prioritate maximă (override 99) și este idempotentă. '
            'Verificare: <code>ssh-audit VM_IP</code> sau '
            '<code>sshd -T | grep -iE "^(kex|cipher|macs|hostkeyalg)"</code> confirmă '
            '<strong>absența completă a algoritmilor vulnerabili</strong>.'
        ),
    },
    '4': {
        'risk_title': 'Risc identificat (fără WAF)',
        'risk_body': (
            'Fără WAF (<strong>W</strong>eb <strong>A</strong>pplication <strong>F</strong>irewall), '
            'atacurile din topul <strong>OWASP</strong> (<strong>O</strong>pen <strong>W</strong>eb '
            '<strong>A</strong>pplication <strong>S</strong>ecurity <strong>P</strong>roject) ajung '
            'direct la aplicație: <code>SQLi</code> (<strong>SQL</strong> <strong>I</strong>njection) '
            'poate exfiltra întreaga bază de date, <code>XSS</code> (<strong>C</strong>ross-<strong>S</strong>ite '
            '<strong>S</strong>cripting) poate fura sesiunile utilizatorilor, '
            '<code>RFI</code> (<strong>R</strong>emote <strong>F</strong>ile <strong>I</strong>nclusion) '
            'poate executa cod de pe servere externe, '
            '<code>Path Traversal</code> poate citi fișiere sistem (<code>/etc/passwd</code>), '
            '<code>Command Injection</code> poate prelua controlul serverului.'
        ),
        'prot_title': 'Protecție implementată (ModSecurity + OWASP CRS)',
        'prot_body': (
            '<strong>ModSecurity</strong> cu <strong>OWASP CRS</strong> (<strong>C</strong>ore '
            '<strong>R</strong>ule <strong>S</strong>et) <strong>3.2.1</strong> (~900 reguli) inspectează '
            'fiecare request HTTP/HTTPS. Operează la <strong>Paranoia Level 2</strong> (moderat) '
            'pentru detecție fiabilă inclusiv a RFI și PHP Injection. Atacurile sunt blocate cu '
            '<strong>HTTP 403 Forbidden</strong> înainte de a ajunge la aplicație și loggate complet în '
            '<code>/var/log/nginx/modsec_audit.log</code>. '
            '<strong>Cum verifici că WAF funcționează:</strong> '
            '<code>curl -k "https://DOMAIN/?id=1+UNION+SELECT+1,2--"</code> → trebuie să returneze 403; '
            '<code>tail -f /var/log/nginx/modsec_audit.log</code> → afișează detalii despre fiecare blocare.'
        ),
        'method': (
            '8 tipuri de atacuri OWASP trimise cu curl la HTTPS endpoint (--insecure, fără SSL verify). '
            'BEFORE: toate primesc 200/301/404 (ajung la backend — neprotejat). '
            'AFTER (Paranoia Level 2): toate primesc 403 Forbidden (blocate de WAF înainte de backend). '
            'Atacurile testate: SQLi UNION, SQLi OR-1=1, XSS script tag, XSS img onerror, '
            'Path Traversal (/etc/passwd), RFI (http://evil.com/shell.php), Command Injection, PHP Injection.'
        ),
        'config':   (
            'nginx + ModSecurity 3: SecRuleEngine On  |  OWASP CRS 3.2.1 (~900 reguli)  |  '
            'Paranoia Level 2 (moderat — RFI + PHP Injection active)  |  '
            'Inbound anomaly score threshold: 5 (o singură regulă critică blochează)'
        ),
        'standard': 'OWASP Top 10 2021 — A03 Injection, A07 XSS, A06 Vulnerable Components; PCI-DSS Req. 6.6 (WAF obligatoriu); NIST SP 800-44',
        'conclusion': (
            'ModSecurity WAF cu OWASP CRS 3.2.1 la Paranoia Level 2 blochează toate cele 8 categorii '
            'de atacuri web demonstrate. Fiecare atac blocat este înregistrat în '
            '<code>/var/log/nginx/modsec_audit.log</code> cu detalii complete: IP sursă, URI, '
            'regulă CRS declanșată (ex: <code>932160</code> pentru RFI, <code>941100</code> pentru XSS, '
            '<code>942100</code> pentru SQLi), timestamp — util pentru <strong>investigație forensică</strong>. '
            'WAF operează transparent față de utilizatorii legitimi. '
            '<strong>Verificare rapidă:</strong> '
            '<code>curl -k "https://DOMAIN/?cmd=;cat+/etc/passwd"</code> → HTTP 403 = WAF activ; '
            '<code>fail2ban-client status</code> + <code>grep "ModSecurity" /var/log/nginx/error.log</code> '
            '= confirmare blocare în loguri.'
        ),
    },
    '5': {
        'risk_title': 'Risc identificat (fără hardening)',
        'risk_body': (
            'MySQL implicit expune mai multe vulnerabilități: <strong>utilizatori anonimi</strong> permit '
            'acces fără autentificare; <strong>baza de date test</strong> este accesibilă public; '
            '<code>local_infile=ON</code> permite citirea fișierelor server; datele din fișierele '
            '<code>.ibd</code> sunt stocate ca <strong>plaintext pe disk</strong> — un furt de backup '
            'sau acces fizic expune toate datele clienților.'
        ),
        'prot_title': 'Protecție implementată (după hardening)',
        'prot_body': (
            'Hardening MySQL în două straturi: (1) <strong>configurare securizată</strong> — eliminare '
            'utilizatori anonimi + test DB, <code>local_infile=OFF</code>, root doar pe localhost; '
            '(2) <strong>TDE (Transparent Data Encryption)</strong> cu plugin <code>keyring_file</code> — '
            'tablespace-urile InnoDB sunt criptate <strong>AES-256</strong>, cheia stocată separat de date.'
        ),
        'method': (
            'Interogări MySQL pentru starea de securitate (utilizatori anonimi, test DB, local_infile, '
            'ENCRYPTION status) + citire directă a fișierului .ibd via PowerShell pentru a demonstra '
            'plaintext vs. criptat. BEFORE: ENCRYPTION=N, strings citibile. AFTER: ENCRYPTION=Y, date criptate.'
        ),
        'config':   'MySQL: remove anonymous users + test DB, local_infile=OFF, keyring_file plugin, innodb_encrypt_tables=ON, innodb_encrypt_log=ON',
        'standard': 'PCI-DSS Req. 3.5 (encryption at rest), CIS MySQL 8.0 Benchmark, GDPR Art. 32 (măsuri tehnice)',
        'conclusion': (
            'Hardening-ul MySQL elimină vulnerabilitățile de configurare implicită și activează criptarea '
            'datelor la rest prin TDE. Cheia de criptare este gestionată de plugin-ul <code>keyring_file</code>, '
            'stocată separat de fișierele de date. Datele sunt <strong>inutilizabile chiar și în cazul '
            'accesului fizic</strong> la fișierele <code>.ibd</code> sau la backup-uri brute. '
            'Conformitatea cu PCI-DSS Req. 3.5 și GDPR Art. 32 este demonstrată prin '
            '<code>ENCRYPTION=Y</code> pe toate tablespace-urile WordPress și business.'
        ),
    },
}


# ---------------------------------------------------------------------------
# CSS — shared between individual and master reports
# ---------------------------------------------------------------------------
def css(accent: str) -> str:
    return f"""
*, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
:root {{
  --bg:     #0d1117;
  --bg2:    #161b22;
  --bg3:    #1f2937;
  --border: #30363d;
  --text:   #c9d1d9;
  --dim:    #8b949e;
  --green:  #3fb950;
  --red:    #f85149;
  --yellow: #d29922;
  --blue:   #58a6ff;
  --purple: #bc8cff;
  --orange: #f0883e;
  --cyan:   #79c0ff;
  --accent: {accent};
  --mono:   'Cascadia Code', 'Fira Code', 'Consolas', 'Courier New', monospace;
  --ui:     -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
}}
html {{ font-size: 15px; scroll-behavior: smooth; }}
body {{ background: var(--bg); color: var(--text); font-family: var(--ui); line-height: 1.5; min-height: 100vh; }}

/* Topbar */
.topbar {{
  position: sticky; top: 0; z-index: 100;
  background: var(--bg2); border-bottom: 2px solid var(--accent);
  display: flex; align-items: center; gap: 12px;
  padding: 10px 24px; box-shadow: 0 2px 12px rgba(0,0,0,.4);
}}
.brand {{ font-weight: 700; color: var(--accent); font-size: .82rem; white-space: nowrap; }}
.demo-id {{
  background: var(--accent); color: #0d1117; font-weight: 800;
  border-radius: 6px; padding: 2px 10px; font-size: .8rem; white-space: nowrap;
}}
.demo-title {{ font-size: .95rem; font-weight: 600; flex: 1; }}
.badge {{ padding: 5px 14px; border-radius: 20px; font-size: .78rem; font-weight: 700; white-space: nowrap; }}
.badge-ok      {{ background: rgba(63,185,80,.15);  color: var(--green);  border: 1px solid rgba(63,185,80,.4); }}
.badge-neutral {{ background: rgba(88,166,255,.12); color: var(--blue);   border: 1px solid rgba(88,166,255,.3); }}
.badge-fail    {{ background: rgba(248,81,73,.15);  color: var(--red);    border: 1px solid rgba(248,81,73,.4); }}

/* Layout */
.container {{ max-width: 1200px; margin: 0 auto; padding: 24px; }}

/* Meta card */
.meta-card {{
  background: var(--bg2); border: 1px solid var(--border);
  border-radius: 8px; padding: 16px 20px; margin-bottom: 20px;
  display: grid; grid-template-columns: max-content 1fr; gap: 2px 20px;
}}
.mk {{ color: var(--dim); font-size: .8rem; padding: 3px 0; }}
.mv {{ color: var(--text); font-size: .82rem; font-family: var(--mono); padding: 3px 0; word-break: break-all; }}

/* Stat chips */
.stats-row {{ display: flex; gap: 10px; flex-wrap: wrap; margin-bottom: 20px; }}
.chip {{
  padding: 6px 14px; border-radius: 20px; font-size: .78rem; font-weight: 600;
  display: inline-flex; align-items: center; gap: 5px;
}}
.chip-red    {{ background: rgba(248,81,73,.12);  color: var(--red);    border: 1px solid rgba(248,81,73,.3); }}
.chip-green  {{ background: rgba(63,185,80,.12);  color: var(--green);  border: 1px solid rgba(63,185,80,.3); }}
.chip-blue   {{ background: rgba(88,166,255,.12); color: var(--blue);   border: 1px solid rgba(88,166,255,.3); }}
.chip-yellow {{ background: rgba(210,153,34,.12); color: var(--yellow); border: 1px solid rgba(210,153,34,.3); }}
.chip-accent {{ background: rgba(0,0,0,.2);       color: var(--accent); border: 1px solid rgba(200,200,200,.15); }}

/* Collapsible sections */
.section {{
  background: var(--bg2); border: 1px solid var(--border);
  border-radius: 8px; margin-bottom: 14px; overflow: hidden;
}}
.section > summary {{
  cursor: pointer; padding: 12px 16px;
  font-weight: 700; font-size: .88rem;
  display: flex; align-items: center; gap: 8px;
  border-bottom: 1px solid transparent; user-select: none; list-style: none;
  transition: background .12s;
}}
.section > summary:hover {{ background: rgba(255,255,255,.03); }}
.section > summary::marker, .section > summary::-webkit-details-marker {{ display: none; }}
.section > summary::before {{
  content: '▶'; font-size: .65rem; color: var(--dim);
  transition: transform .15s; flex-shrink: 0;
}}
.section[open] > summary::before {{ transform: rotate(90deg); }}
.section[open] > summary {{ border-bottom-color: var(--border); }}

.sec-before {{ color: var(--red); }}
.sec-after  {{ color: var(--green); }}
.sec-diff   {{ color: var(--yellow); }}
.sec-full   {{ color: var(--dim); }}
.sec-nav    {{ color: var(--blue); }}

/* Log block */
.log-block {{
  font-family: var(--mono); font-size: .79rem; line-height: 1.65;
  padding: 14px 16px; overflow-x: auto; background: var(--bg);
}}
.scroll-h {{ max-height: 520px; overflow-y: auto; }}

/* Log line classes */
.ll       {{ display: block; white-space: pre; }}
.ll-empty {{ display: block; height: .7em; }}
.banner   {{ color: var(--accent); font-weight: 700; }}
.sec-good {{ color: var(--green);  font-weight: 600; }}
.sec-bad  {{ color: var(--red);    font-weight: 600; }}
.ok       {{ color: #57ab5a; }}
.fail     {{ color: var(--red); }}
.warn     {{ color: var(--yellow); }}
.sec-hdr  {{ color: var(--cyan); font-weight: 700; }}
.item     {{ color: var(--text); }}
.normal   {{ color: var(--text); }}

/* Diff block */
.diff-block {{
  font-family: var(--mono); font-size: .79rem; line-height: 1.65;
  padding: 14px 16px; overflow-x: auto; background: var(--bg);
}}
.df-add  {{ color: var(--green);  background: rgba(63,185,80,.06);  display: block; }}
.df-del  {{ color: var(--red);    background: rgba(248,81,73,.06);  display: block; }}
.df-ctx  {{ color: var(--dim);    display: block; }}
.df-hunk {{ color: var(--cyan);   display: block; font-style: italic; }}
.df-meta {{ color: var(--dim);    display: block; opacity: .7; }}
.no-diff {{ padding: 14px 16px; color: var(--dim); font-style: italic; font-size: .85rem; }}

/* Nav links (master report) */
.nav-grid {{
  display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  gap: 10px; padding: 16px;
}}
.nav-card {{
  background: var(--bg3); border: 1px solid var(--border); border-radius: 6px;
  padding: 12px 14px; text-decoration: none; color: var(--text);
  display: flex; flex-direction: column; gap: 4px;
  transition: border-color .15s, background .15s;
}}
.nav-card:hover {{ border-color: var(--accent); background: var(--bg2); }}
.nav-card .nc-icon {{ font-size: 1.4rem; }}
.nav-card .nc-title {{ font-weight: 700; font-size: .85rem; color: var(--accent); }}
.nav-card .nc-sub {{ font-size: .75rem; color: var(--dim); }}

/* Explanation section (non-collapsible context card) */
.explain-section {{
  background: var(--bg2); border: 1px solid var(--border);
  border-radius: 8px; margin-bottom: 14px; overflow: hidden;
}}
.explain-section-title {{
  padding: 12px 16px; font-weight: 700; font-size: .88rem;
  color: var(--cyan); border-bottom: 1px solid var(--border);
  display: flex; align-items: center; gap: 8px;
}}
.explain-grid {{
  display: grid; grid-template-columns: 1fr 1fr; gap: 14px; padding: 16px;
}}
@media (max-width: 700px) {{ .explain-grid {{ grid-template-columns: 1fr; }} }}
.explain-card {{
  border-radius: 6px; padding: 14px 16px;
}}
.explain-card.risk {{
  background: rgba(248,81,73,.07);
  border: 1px solid rgba(248,81,73,.22);
}}
.explain-card.prot {{
  background: rgba(63,185,80,.07);
  border: 1px solid rgba(63,185,80,.22);
}}
.explain-card h4 {{
  font-size: .77rem; font-weight: 700; margin-bottom: 9px;
  text-transform: uppercase; letter-spacing: .05em;
}}
.explain-card.risk h4 {{ color: var(--red); }}
.explain-card.prot h4 {{ color: var(--green); }}
.explain-card p {{ font-size: .83rem; color: var(--text); line-height: 1.65; }}
.explain-card p code {{
  background: rgba(255,255,255,.09); border-radius: 3px;
  padding: 1px 5px; font-family: var(--mono); font-size: .78rem;
}}
.explain-card.risk p strong {{ color: #f0887a; }}
.explain-card.prot p strong {{ color: #57c26a; }}
.info-rows {{
  padding: 10px 16px 14px; border-top: 1px solid var(--border);
  display: grid; grid-template-columns: max-content 1fr; gap: 7px 16px;
  font-size: .8rem;
}}
.ir-key {{
  color: var(--dim); white-space: nowrap; padding-top: 2px;
  font-size: .77rem; text-transform: uppercase; letter-spacing: .04em;
}}
.ir-val {{ color: var(--text); font-family: var(--mono); font-size: .78rem; word-break: break-word; line-height: 1.5; }}
.std-tag {{
  display: inline-block; background: rgba(88,166,255,.09);
  border: 1px solid rgba(88,166,255,.22); color: var(--blue);
  border-radius: 4px; padding: 2px 8px; font-size: .74rem;
  font-family: var(--ui); margin: 1px 3px 1px 0;
}}

/* Conclusion box */
.conclusion-box {{
  background: rgba(63,185,80,.06);
  border: 1px solid rgba(63,185,80,.22);
  border-left: 4px solid var(--green);
  border-radius: 6px; padding: 18px 22px; margin-top: 20px;
}}
.conclusion-box h3 {{
  color: var(--green); font-size: .82rem; font-weight: 700;
  margin-bottom: 10px; text-transform: uppercase; letter-spacing: .05em;
  display: flex; align-items: center; gap: 8px;
}}
.conclusion-box p {{ color: var(--text); font-size: .84rem; line-height: 1.75; }}
.conclusion-box p code {{
  background: rgba(255,255,255,.09); border-radius: 3px;
  padding: 1px 5px; font-family: var(--mono); font-size: .79rem;
}}
.conclusion-box p strong {{ color: #57c26a; }}

/* Footer */
footer {{
  margin-top: 32px; padding: 18px 0;
  border-top: 1px solid var(--border);
  text-align: center; color: var(--dim); font-size: .78rem; line-height: 1.8;
}}
footer strong {{ color: var(--accent); }}

/* Scrollbar */
::-webkit-scrollbar {{ width: 6px; height: 6px; }}
::-webkit-scrollbar-track {{ background: var(--bg); }}
::-webkit-scrollbar-thumb {{ background: var(--border); border-radius: 3px; }}
::-webkit-scrollbar-thumb:hover {{ background: var(--dim); }}

/* Print */
@media print {{
  .topbar {{ position: static; }}
  details, details[open] {{ display: block; }}
  details > summary {{ display: none; }}
  .log-block, .diff-block, .scroll-h {{ max-height: none !important; overflow: visible; page-break-inside: avoid; }}
  .explain-section, .conclusion-box {{ page-break-inside: avoid; }}
}}
"""


# ---------------------------------------------------------------------------
# Explanation section HTML (shown always — non-collapsible)
# ---------------------------------------------------------------------------
def explanation_section_html(num: str) -> str:
    expl = DEMO_EXPLANATIONS.get(num)
    if not expl:
        return ''

    stds = [s.strip() for s in expl['standard'].split(',')]
    std_tags = ''.join(f'<span class="std-tag">{html_mod.escape(s)}</span>' for s in stds)
    config_esc = html_mod.escape(expl['config'])
    method_esc = html_mod.escape(expl['method'])

    return f"""
  <div class="explain-section">
    <div class="explain-section-title">
      📋 Descriere demo &amp; context de securitate
    </div>
    <div class="explain-grid">
      <div class="explain-card risk">
        <h4>⚠ {html_mod.escape(expl['risk_title'])}</h4>
        <p>{expl['risk_body']}</p>
      </div>
      <div class="explain-card prot">
        <h4>✓ {html_mod.escape(expl['prot_title'])}</h4>
        <p>{expl['prot_body']}</p>
      </div>
    </div>
    <div class="info-rows">
      <span class="ir-key">Metodă testare</span>
      <span class="ir-val">{method_esc}</span>
      <span class="ir-key">Configurație</span>
      <span class="ir-val">{config_esc}</span>
      <span class="ir-key">Standard</span>
      <span class="ir-val">{std_tags}</span>
    </div>
  </div>"""


# ---------------------------------------------------------------------------
# Conclusion box HTML (shown always — below diff)
# ---------------------------------------------------------------------------
def conclusion_section_html(num: str) -> str:
    expl = DEMO_EXPLANATIONS.get(num)
    if not expl:
        return ''
    return f"""
  <div class="conclusion-box">
    <h3>✅ Concluzie — Ce am demonstrat</h3>
    <p>{expl['conclusion']}</p>
  </div>"""


# ---------------------------------------------------------------------------
# Individual demo HTML
# ---------------------------------------------------------------------------
def generate_individual_html(args, before_lines, after_lines, full_log_lines,
                             tde_before_lines=None, tde_after_lines=None) -> str:
    now = datetime.now().strftime('%d %B %Y, %H:%M:%S')
    num = args.demo_num or '?'
    meta = DEMO_META.get(num, DEMO_META['ALL'])
    accent = meta['color']
    icon = meta['icon']

    stats = count_stats(before_lines, after_lines)
    title = args.title
    subtitle = args.subtitle or ''
    target = args.target or 'N/A'
    duration = args.duration or 'N/A'

    if args.badge_text:
        badge_cls = 'badge-ok'
        badge_txt = args.badge_text
    elif stats['blocked_after'] > 0:
        badge_cls = 'badge-ok'
        badge_txt = f'✓ {stats["blocked_after"]} ATACURI BLOCATE'
    elif stats['changed'] > 0:
        badge_cls = 'badge-ok'
        badge_txt = f'✓ {stats["changed"]} MODIFICĂRI APLICATE'
    else:
        badge_cls = 'badge-ok'
        badge_txt = '✓ DEMO FINALIZAT'

    logo_txt = f'Demo {num}' if num not in ('?', 'ALL') else 'Demo ALL'

    b_html = render_lines(before_lines)
    a_html = render_lines(after_lines)
    d_html = diff_html(before_lines, after_lines)
    expl_html = explanation_section_html(num)
    concl_html = conclusion_section_html(num)

    tde_section = ''
    if tde_before_lines or tde_after_lines:
        tb_lines = tde_before_lines or []
        ta_lines = tde_after_lines or []
        tb_html = render_lines(tb_lines)
        ta_html = render_lines(ta_lines)
        td_html = diff_html(tb_lines, ta_lines)
        tde_section = f"""
  <details class="section" open>
    <summary class="sec-before">🔒 TDE BEFORE — tablespace-uri necriptate (ENCRYPTION=N, keyring plugin inactiv)</summary>
    <div class="log-block">{tb_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-after">🔐 TDE AFTER — tablespace-uri criptate AES-256 (ENCRYPTION=Y, keyring_file ACTIVE)</summary>
    <div class="log-block">{ta_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-diff">🔀 DIFF TDE — înainte vs după criptare (roșu = stare necriptată, verde = stare criptată)</summary>
    <div class="diff-block">{td_html}</div>
  </details>"""

    full_section = ''
    if full_log_lines:
        fl = render_lines(full_log_lines)
        full_section = f"""
  <details class="section">
    <summary class="sec-full">📋 Session Log Complet</summary>
    <div class="log-block scroll-h">{fl}</div>
  </details>"""

    sub_row = (f'<span class="mk">Descriere</span>'
               f'<span class="mv">{esc(subtitle)}</span>') if subtitle else ''

    changed_chip = (f'<span class="chip chip-yellow">🔄 {stats["changed"]} modificări Ansible</span>'
                    if stats['changed'] > 0 else '')

    before_label = args.before_label or 'BEFORE — Stare inițială (fără hardening)'
    after_label  = args.after_label  or 'AFTER — Stare finală (hardening aplicat)'

    return f"""<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} — SC IT SECURITY SRL</title>
<style>{css(accent)}</style>
</head>
<body>

<div class="topbar">
  <span class="brand">SC IT SECURITY SRL</span>
  <span class="demo-id">{logo_txt}</span>
  <span class="demo-title">{icon} {esc(title)}</span>
  <span class="badge {badge_cls}">{badge_txt}</span>
</div>

<div class="container">

  <div class="meta-card">
    <span class="mk">Target</span>        <span class="mv">{esc(target)}</span>
    <span class="mk">Data execuției</span> <span class="mv">{now}</span>
    <span class="mk">Durată totală</span>  <span class="mv">{esc(duration)}</span>
    <span class="mk">Playbook</span>       <span class="mv">ansible-playbook playbooks/5-harden-security.yml --tags {esc(meta['label'].lower().replace(' ', '_').replace('+', '').replace('/', ''))}</span>
    {sub_row}
  </div>

  <div class="stats-row">
    <span class="chip chip-red">🔴 BEFORE: {stats['ok_before']} permise, {stats['blocked_before']} blocate</span>
    <span class="chip chip-green">🟢 AFTER: {stats['ok_after']} permise, {stats['blocked_after']} blocate</span>
    <span class="chip chip-blue">⏱ Durată: {esc(duration)}</span>
    {changed_chip}
  </div>

  {expl_html}

  <details class="section" open>
    <summary class="sec-before">🔴 {esc(before_label)}</summary>
    <div class="log-block">{b_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-after">🟢 {esc(after_label)}</summary>
    <div class="log-block">{a_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-diff">🔀 DIFF — Comparație Before vs After (roșu = eliminat din starea inițială, verde = adăugat după hardening)</summary>
    <div class="diff-block">{d_html}</div>
  </details>

  {tde_section}

  {full_section}

  {concl_html}

</div>

<footer>
  <strong>SC MEDIA SRL</strong> — infrastructură cloud Azure &nbsp;·&nbsp;
  furnizor: <strong>SC IT SECURITY SRL</strong><br>
  Disertație Master 2026 &nbsp;·&nbsp; raport generat automat &nbsp;·&nbsp; {now}
</footer>
</body>
</html>"""


# ---------------------------------------------------------------------------
# Master report HTML (demo-all-hardenings.sh)
# ---------------------------------------------------------------------------
def generate_master_html(args, full_log_lines, nav_pairs) -> str:
    now = datetime.now().strftime('%d %B %Y, %H:%M:%S')
    accent = '#58a6ff'

    title = args.title
    duration = args.duration or 'N/A'
    target = args.target or 'toate VM-urile'

    fl_html = render_lines(full_log_lines) if full_log_lines else ''

    # Navigation cards
    nav_cards_html = ''
    if nav_pairs:
        cards = []
        for entry in nav_pairs:
            parts = entry.split(':', 1)
            if len(parts) == 2:
                card_num_s, card_path = parts
                card_num_s = card_num_s.strip()
                card_meta = DEMO_META.get(card_num_s, DEMO_META['ALL'])
                cards.append(
                    f'<a class="nav-card" href="{html_mod.escape(card_path)}" target="_blank">'
                    f'<span class="nc-icon">{card_meta["icon"]}</span>'
                    f'<span class="nc-title">Demo {card_num_s} — {html_mod.escape(card_meta["label"])}</span>'
                    f'<span class="nc-sub">Click pentru raport detaliat</span>'
                    f'</a>'
                )
        if cards:
            nav_cards_html = f"""
  <details class="section" open>
    <summary class="sec-nav">🗂 Rapoarte individuale — click pentru detalii</summary>
    <div class="nav-grid">{''.join(cards)}</div>
  </details>"""

    full_section = ''
    if fl_html:
        full_section = f"""
  <details class="section">
    <summary class="sec-full">📋 Session Log Complet (toate hardeningurile)</summary>
    <div class="log-block scroll-h">{fl_html}</div>
  </details>"""

    # Summary table — demos that have explanation entries
    demo_rows = ''.join(
        f'<tr>'
        f'<td>{m["icon"]}</td>'
        f'<td><strong>Demo {k}</strong></td>'
        f'<td style="color:var(--dim)">{m["label"]}</td>'
        f'<td style="font-family:var(--mono);font-size:.75rem;color:var(--dim)">'
        f'{html_mod.escape(DEMO_EXPLANATIONS[k]["standard"][:60])}…</td>'
        f'<td><span class="badge badge-ok" style="font-size:.72rem">✓ APLICAT</span></td>'
        f'</tr>'
        for k, m in DEMO_META.items()
        if k not in ('ALL', 'CERT') and k in DEMO_EXPLANATIONS
    )

    # Master conclusion
    master_conclusion = """
  <div class="conclusion-box">
    <h3>✅ Concluzie generală — infrastructura SC MEDIA SRL securizată</h3>
    <p>
      Cele 5 hardeninguri demonstrate acoperă principalele categorii de risc identificate în auditul
      de securitate al infrastructurii cloud Azure a SC MEDIA SRL:
      <strong>brute-force</strong> (rate limiting + Fail2ban),
      <strong>criptografie slabă</strong> (SSH hardening),
      <strong>atacuri web OWASP Top 10</strong> (ModSecurity WAF),
      <strong>date neprotejate la rest</strong> (MySQL TDE).
      Toate măsurile sunt implementate prin <strong>Ansible playbooks</strong> idempotente, reproductibile
      și auditabile, cu dovezi before/after pentru fiecare hardening.
      Infrastructura respectă recomandările <strong>CIS Benchmarks</strong>, <strong>OWASP</strong>,
      <strong>NIST SP 800-53</strong> și cerințele <strong>GDPR Art. 32</strong> privind măsurile tehnice
      adecvate de securitate.
    </p>
  </div>"""

    return f"""<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)} — SC IT SECURITY SRL</title>
<style>
{css(accent)}
.sum-table {{ width: 100%; border-collapse: collapse; font-size: .85rem; }}
.sum-table th {{ color: var(--dim); font-weight: 600; padding: 8px 12px;
                  border-bottom: 1px solid var(--border); text-align: left; }}
.sum-table td {{ padding: 8px 12px; border-bottom: 1px solid rgba(48,54,61,.5); vertical-align: middle; }}
.sum-table tr:last-child td {{ border-bottom: none; }}
.sum-table tr:hover td {{ background: rgba(255,255,255,.02); }}
</style>
</head>
<body>

<div class="topbar">
  <span class="brand">SC IT SECURITY SRL</span>
  <span class="demo-id">Demo ALL</span>
  <span class="demo-title">🔒 {esc(title)}</span>
  <span class="badge badge-ok">✓ 5/5 HARDENINGURI APLICATE</span>
</div>

<div class="container">

  <div class="meta-card">
    <span class="mk">Target</span>        <span class="mv">{esc(target)}</span>
    <span class="mk">Data execuției</span> <span class="mv">{now}</span>
    <span class="mk">Durată totală</span>  <span class="mv">{esc(duration)}</span>
    <span class="mk">Mediu</span>          <span class="mv">Microsoft Azure — Sweden Central — rg-mediasrl-productie-swedencentral</span>
    <span class="mk">Playbook</span>       <span class="mv">ansible-playbook playbooks/5-harden-security.yml</span>
    <span class="mk">Orchestrator</span>  <span class="mv">scripts/demo-all-hardenings.sh</span>
  </div>

  <div class="stats-row">
    <span class="chip chip-green">✅ 5 hardeninguri aplicate</span>
    <span class="chip chip-blue">⏱ Durată totală: {esc(duration)}</span>
    <span class="chip chip-accent">🔒 Infrastructură securizată</span>
    <span class="chip chip-yellow">📋 Rapoarte individuale disponibile mai jos</span>
  </div>

  <details class="section" open>
    <summary class="sec-after">📊 Sumar hardeninguri aplicate</summary>
    <div style="padding: 0 0 4px">
      <table class="sum-table">
        <thead><tr><th></th><th>Demo</th><th>Hardening</th><th>Standard acoperit</th><th>Status</th></tr></thead>
        <tbody>{demo_rows}</tbody>
      </table>
    </div>
  </details>

  {nav_cards_html}
  {full_section}
  {master_conclusion}

</div>

<footer>
  <strong>SC MEDIA SRL</strong> — infrastructură cloud Azure &nbsp;·&nbsp;
  furnizor: <strong>SC IT SECURITY SRL</strong><br>
  Disertație Master 2026 &nbsp;·&nbsp; raport master generat automat &nbsp;·&nbsp; {now}
</footer>
</body>
</html>"""


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main():
    p = argparse.ArgumentParser(description='Security demo HTML report generator')
    p.add_argument('--title',        required=True)
    p.add_argument('--subtitle',     default='')
    p.add_argument('--before',       default='')
    p.add_argument('--after',        default='')
    p.add_argument('--before-label', default='', dest='before_label')
    p.add_argument('--after-label',  default='', dest='after_label')
    p.add_argument('--full-log',     default='', dest='full_log')
    p.add_argument('--target',       default='')
    p.add_argument('--duration',     default='')
    p.add_argument('--demo-num',     default='', dest='demo_num')
    p.add_argument('--html',         required=True)
    p.add_argument('--nav',          default='',
                   help='Space-separated "num:relative-path.html" pairs for master report')
    p.add_argument('--badge',        default='', dest='badge_text',
                   help='Custom badge text override (e.g. "✓ 1 IP BANAT"). Skips auto-detection.')
    p.add_argument('--meta-json',    default='', dest='meta_json',
                   help='JSON string with demo metadata: icon, color, label, risk_title, risk_body, '
                        'prot_title, prot_body, method, config, standard, conclusion. '
                        'Injected at runtime into DEMO_META/DEMO_EXPLANATIONS — no file edits needed.')
    p.add_argument('--tde-before',   default='', dest='tde_before',
                   help='TDE before-state file (demo-5 only)')
    p.add_argument('--tde-after',    default='', dest='tde_after',
                   help='TDE after-state file (demo-5 only)')
    args = p.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.html)), exist_ok=True)

    # Inject runtime metadata from --meta-json (for demos outside 1-5)
    if args.meta_json and args.demo_num not in ('', '?', 'ALL'):
        import json as _json
        try:
            m = _json.loads(args.meta_json)
            num = args.demo_num
            DEMO_META[num] = {
                'icon':  m.get('icon',  '🔒'),
                'color': m.get('color', '#58a6ff'),
                'label': m.get('label', f'Demo {num}'),
            }
            DEMO_EXPLANATIONS[num] = {
                'risk_title': m.get('risk_title', 'Risc identificat'),
                'risk_body':  m.get('risk_body',  ''),
                'prot_title': m.get('prot_title', 'Protecție implementată'),
                'prot_body':  m.get('prot_body',  ''),
                'method':     m.get('method',     ''),
                'config':     m.get('config',     ''),
                'standard':   m.get('standard',   ''),
                'conclusion': m.get('conclusion', ''),
            }
        except _json.JSONDecodeError as e:
            print(f'[WARN] --meta-json parse error: {e}', flush=True)

    before_lines      = read_file(args.before)
    after_lines       = read_file(args.after)
    full_log_lines    = read_file(args.full_log)
    tde_before_lines  = read_file(args.tde_before)
    tde_after_lines   = read_file(args.tde_after)

    if args.demo_num == 'ALL':
        nav_pairs = args.nav.split() if args.nav else []
        content = generate_master_html(args, full_log_lines, nav_pairs)
    else:
        content = generate_individual_html(args, before_lines, after_lines, full_log_lines,
                                           tde_before_lines, tde_after_lines)

    with open(args.html, 'w', encoding='utf-8') as f:
        f.write(content)

    size_kb = os.path.getsize(args.html) // 1024
    print(f'[HTML] {args.html} ({size_kb} KB)')


if __name__ == '__main__':
    main()
