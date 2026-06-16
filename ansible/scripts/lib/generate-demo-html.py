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
        --before   logs/security-demos/rate-limit-before.txt \
        --after    logs/security-demos/rate-limit-after.txt \
        --target   "mediasrl.swedencentral.cloudapp.azure.com" \
        --demo-num 1 \
        --duration "47s" \
        --html     logs/security-demos/demo-1-rate-limiting-2026-06-13.html

    # Master report (demo-all-hardenings.sh):
    python3 generate-demo-html.py \
        --title    "Security Hardening — Demonstratie completa" \
        --demo-num ALL \
        --full-log logs/security-demos/security-demo-report-TIMESTAMP.txt \
        --nav      "Rate Limiting:demo-1.html Fail2ban:demo-2.html ..." \
        --duration "18m" \
        --html     logs/security-demos/security-demo-report-TIMESTAMP.html
"""

import argparse
import re
import os
import sys
import html as html_mod
from datetime import datetime
import difflib

# ---------------------------------------------------------------------------
# ANSI / text helpers
# ---------------------------------------------------------------------------
ANSI_RE = re.compile(r'\x1b\[[0-9;]*m')


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)


def esc(s: str) -> str:
    return html_mod.escape(strip_ansi(s).rstrip('\n'))


# ---------------------------------------------------------------------------
# Line classification (drives CSS coloring)
# ---------------------------------------------------------------------------
def classify_line(raw_line: str) -> str:
    s = strip_ansi(raw_line).upper().strip()
    if not s:
        return 'empty'

    # Banner / box-drawing lines (╔ ╚ ║ etc.)
    if re.search(r'[╔╠╚╗╝║╣]', strip_ansi(raw_line)):
        return 'banner'

    # === Strong security POSITIVE (blocked / protected / encrypted) ===
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

    # === Strong security NEGATIVE (vulnerable / not blocked) ===
    if re.search(
        r'NOT BLOCKED|← NOT BLOCKED|PASSED \d{3}|'
        r'\[WEAK FOUND\]|ENCRYPTION\s*=\s*N\b|'
        r'WARNING.*READABLE|SOME READABLE',
        s
    ):
        return 'sec-bad'

    # General OK
    if re.search(
        r'\b(OK|PASS|COMPLETE|SUCCESS|ACTIVE|RUNNING|INSTALLED|'
        r'REACHABLE|ALLOW|ENABLED|ALLOW[EE]D)\b', s
    ):
        return 'ok'

    # General fail
    if re.search(r'\b(FAIL|ERROR|FATAL|UNREACHABLE)\b', s):
        return 'fail'

    # Warning
    if re.search(r'\bWARN\b|CAUTION|DEPRECATED|DOWNTIME', s):
        return 'warn'

    # Section headers
    if re.search(r'^===\s+|^STEP\s+\d|^SUMMARY\s*[\[\(]|^HARDENING\s+\d', s):
        return 'sec-hdr'

    # Numbered request / attempt lines
    if re.search(r'(REQUEST|ATTEMPT)\s+\d+\s*:', s):
        return 'item'

    return 'normal'


# ---------------------------------------------------------------------------
# Render log lines → HTML
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
# Unified diff → HTML
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
# Demo metadata
# ---------------------------------------------------------------------------
DEMO_META = {
    '1':    {'icon': '⚡',   'color': '#f0883e', 'label': 'nginx Rate Limiting'},
    '2':    {'icon': '🛡️',  'color': '#d29922', 'label': 'Fail2ban'},
    '3':    {'icon': '🔐',  'color': '#79c0ff', 'label': 'SSH Hardening'},
    '4':    {'icon': '🧱',  'color': '#3fb950', 'label': 'ModSecurity WAF'},
    '5':    {'icon': '💾',  'color': '#bc8cff', 'label': 'MySQL Hardening + TDE'},
    'ALL':  {'icon': '🔒',  'color': '#58a6ff', 'label': 'Security Hardening Demo'},
    'CERT': {'icon': '🔏',  'color': '#79c0ff', 'label': "Let's Encrypt TLS"},
}


# ---------------------------------------------------------------------------
# CSS (shared between individual and master reports)
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

/* ── Topbar ── */
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

/* ── Layout ── */
.container {{ max-width: 1200px; margin: 0 auto; padding: 24px; }}

/* ── Meta card ── */
.meta-card {{
  background: var(--bg2); border: 1px solid var(--border);
  border-radius: 8px; padding: 16px 20px; margin-bottom: 20px;
  display: grid; grid-template-columns: max-content 1fr; gap: 2px 20px;
}}
.mk {{ color: var(--dim); font-size: .8rem; padding: 3px 0; }}
.mv {{ color: var(--text); font-size: .82rem; font-family: var(--mono); padding: 3px 0; word-break: break-all; }}

/* ── Stat chips ── */
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

/* ── Sections (collapsible) ── */
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

/* ── Log block ── */
.log-block {{
  font-family: var(--mono); font-size: .79rem; line-height: 1.65;
  padding: 14px 16px; overflow-x: auto; background: var(--bg);
}}
.scroll-h {{ max-height: 520px; overflow-y: auto; }}

/* ── Log line classes ── */
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

/* ── Diff block ── */
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

/* ── Nav links (master report) ── */
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

/* ── Footer ── */
footer {{
  margin-top: 32px; padding: 18px 0;
  border-top: 1px solid var(--border);
  text-align: center; color: var(--dim); font-size: .78rem; line-height: 1.8;
}}
footer strong {{ color: var(--accent); }}

/* ── Scrollbar ── */
::-webkit-scrollbar {{ width: 6px; height: 6px; }}
::-webkit-scrollbar-track {{ background: var(--bg); }}
::-webkit-scrollbar-thumb {{ background: var(--border); border-radius: 3px; }}
::-webkit-scrollbar-thumb:hover {{ background: var(--dim); }}

/* ── Print ── */
@media print {{
  .topbar {{ position: static; }}
  details, details[open] {{ display: block; }}
  details > summary {{ display: none; }}
  .log-block, .diff-block, .scroll-h {{ max-height: none !important; overflow: visible; page-break-inside: avoid; }}
}}
"""


# ---------------------------------------------------------------------------
# Individual demo HTML
# ---------------------------------------------------------------------------
def generate_individual_html(args, before_lines, after_lines, full_log_lines) -> str:
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

    # Overall badge
    if stats['blocked_after'] > 0:
        badge_cls = 'badge-ok'
        badge_txt = f'✓ {stats["blocked_after"]} ATACURI BLOCATE'
    elif stats['changed'] > 0:
        badge_cls = 'badge-ok'
        badge_txt = f'✓ {stats["changed"]} MODIFICĂRI APLICATE'
    else:
        badge_cls = 'badge-neutral'
        badge_txt = '✓ DEMO FINALIZAT'

    logo_txt = f'Demo {num}' if num not in ('?', 'ALL') else 'Demo ALL'

    b_html = render_lines(before_lines)
    a_html = render_lines(after_lines)
    d_html = diff_html(before_lines, after_lines)

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

    before_label = args.before_label or 'BEFORE: Stare inițială'
    after_label  = args.after_label  or 'AFTER: Stare finală'

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
    <span class="mk">Playbook</span>       <span class="mv">ansible-playbook playbooks/5-harden-security.yml</span>
    {sub_row}
  </div>

  <div class="stats-row">
    <span class="chip chip-red">🔴 BEFORE: {stats['ok_before']} pass, {stats['blocked_before']} blocate</span>
    <span class="chip chip-green">🟢 AFTER: {stats['ok_after']} pass, {stats['blocked_after']} blocate</span>
    <span class="chip chip-blue">⏱ {esc(duration)}</span>
    {changed_chip}
  </div>

  <details class="section" open>
    <summary class="sec-before">🔴 {esc(before_label)}</summary>
    <div class="log-block">{b_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-after">🟢 {esc(after_label)}</summary>
    <div class="log-block">{a_html}</div>
  </details>

  <details class="section" open>
    <summary class="sec-diff">🔀 DIFF: Before vs After</summary>
    <div class="diff-block">{d_html}</div>
  </details>

  {full_section}

</div>

<footer>
  <strong>SC MEDIA SRL</strong> — infrastructură cloud Azure &nbsp;·&nbsp;
  furnizor: <strong>SC IT SECURITY SRL</strong><br>
  Disertație Master 2026 &nbsp;·&nbsp; generat automat · {now}
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
    # nav_pairs format: ["1:demo-1-rate-limiting-....html", "2:demo-2-....html", ...]
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
                    f'<span class="nc-title">Demo {card_num_s}</span>'
                    f'<span class="nc-sub">{html_mod.escape(card_meta["label"])}</span>'
                    f'</a>'
                )
        if cards:
            nav_cards_html = f"""
  <details class="section" open>
    <summary class="sec-nav">🗂 Rapoarte individuale per hardening</summary>
    <div class="nav-grid">{''.join(cards)}</div>
  </details>"""

    full_section = ''
    if fl_html:
        full_section = f"""
  <details class="section">
    <summary class="sec-full">📋 Session Log Complet (toate hardeningurile)</summary>
    <div class="log-block scroll-h">{fl_html}</div>
  </details>"""

    # Summary table
    summary_rows = ''.join(
        f'<tr><td>{m["icon"]}</td><td><strong>Demo {k}</strong></td>'
        f'<td style="color:var(--dim)">{m["label"]}</td>'
        f'<td><span class="badge badge-ok" style="font-size:.72rem">✓ APLICAT</span></td></tr>'
        for k, m in DEMO_META.items() if k != 'ALL'
    )

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
.sum-table td {{ padding: 8px 12px; border-bottom: 1px solid rgba(48,54,61,.5); }}
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
    <span class="mk">Mediu</span>          <span class="mv">Azure — Sweden Central — rg-mediasrl-productie-swedencentral</span>
    <span class="mk">Playbook</span>       <span class="mv">ansible-playbook playbooks/5-harden-security.yml</span>
  </div>

  <div class="stats-row">
    <span class="chip chip-green">✅ 5 hardeninguri aplicate</span>
    <span class="chip chip-blue">⏱ Durată totală: {esc(duration)}</span>
    <span class="chip chip-accent">🔒 Infrastructură securizată</span>
  </div>

  <!-- Summary table -->
  <details class="section" open>
    <summary class="sec-after">📊 Sumar hardeninguri aplicate</summary>
    <div style="padding: 0 0 4px">
      <table class="sum-table">
        <thead><tr><th></th><th>Demo</th><th>Hardening</th><th>Status</th></tr></thead>
        <tbody>{summary_rows}</tbody>
      </table>
    </div>
  </details>

  {nav_cards_html}
  {full_section}

</div>

<footer>
  <strong>SC MEDIA SRL</strong> — infrastructură cloud Azure &nbsp;·&nbsp;
  furnizor: <strong>SC IT SECURITY SRL</strong><br>
  Disertație Master 2026 &nbsp;·&nbsp; raport master generat automat · {now}
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
                   help='Space-separated "Title:relative-path.html" pairs for master report')
    args = p.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(args.html)), exist_ok=True)

    before_lines   = read_file(args.before)
    after_lines    = read_file(args.after)
    full_log_lines = read_file(args.full_log)

    if args.demo_num == 'ALL':
        nav_pairs = args.nav.split() if args.nav else []
        content = generate_master_html(args, full_log_lines, nav_pairs)
    else:
        content = generate_individual_html(args, before_lines, after_lines, full_log_lines)

    with open(args.html, 'w', encoding='utf-8') as f:
        f.write(content)

    size_kb = os.path.getsize(args.html) // 1024
    print(f'[HTML] {args.html} ({size_kb} KB)')


if __name__ == '__main__':
    main()
