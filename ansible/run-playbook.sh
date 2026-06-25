#!/usr/bin/env bash
# =============================================================================
# run-playbook.sh — Ansible playbook wrapper with timestamped logs + HTML report
#
# Usage:
#   ./scripts/run-playbook.sh <playbook> [ansible-playbook options...]
#
# Examples:
#   ./run-playbook.sh playbooks/1-setup-ssh-keys.yml --ask-pass
#   ./run-playbook.sh playbooks/2-site.yml
#   ./run-playbook.sh playbooks/2-site.yml --tags nginx,wordpress
#   ./run-playbook.sh playbooks/2-site.yml --limit vm-web-01 -v
#
# Output files (logs/ directory):
#   YYYY-MM-DD_HH-MM-SS_<playbook>.log        (ANSI color — view in terminal)
#   YYYY-MM-DD_HH-MM-SS_<playbook>.clean.log  (plain text — view in editors)
#   YYYY-MM-DD_HH-MM-SS_<playbook>.html       (HTML report — open in browser)
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

# ── Log file names ─────────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
PLAYBOOK_NAME="$(basename "${PLAYBOOK}" .yml)"
LOG_FILE="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.log"
LOG_FILE_CLEAN="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.clean.log"
HTML_FILE="${LOGS_DIR}/${TIMESTAMP}_${PLAYBOOK_NAME}.html"

# ── Force colors even when stdout is piped ────────────────────────────────────
export ANSIBLE_FORCE_COLOR=1

# ── Suppress paramiko TripleDES deprecation warnings (system library issue) ──
export PYTHONWARNINGS="ignore::DeprecationWarning"

# ── Suppress Ansible reserved-variable warnings (azure_rm plugin sets         ──
# ──   'name' and 'tags' as host vars which collide with Ansible magic vars)   ──
export ANSIBLE_SYSTEM_WARNINGS=false

# ── Record start time ─────────────────────────────────────────────────────────
START_SECONDS="${SECONDS}"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
EXTRA_ARGS="${*:-(none)}"

# ── strip_ansi: remove ANSI escape sequences ──────────────────────────────────
strip_ansi() { sed 's/\x1b\[[0-9;]*[mGKHF]//g; s/\x1b\[[0-9;]*[ABCD]//g'; }

# ── Header ────────────────────────────────────────────────────────────────────
HEADER=$(cat <<EOF
================================================================
  ANSIBLE EXECUTION LOG
================================================================
  Playbook  : ${PLAYBOOK}
  Started   : ${START_TIME}
  User      : $(whoami)@$(hostname)
  Directory : ${ANSIBLE_DIR}
  Extra args: ${EXTRA_ARGS}
================================================================

EOF
)
echo "${HEADER}" | tee "${LOG_FILE}" | tee >(strip_ansi >> "${LOG_FILE_CLEAN}") > /dev/null
echo "${HEADER}"

# ── Run playbook ──────────────────────────────────────────────────────────────
# Pipeline: raw output → ANSI log (full) → filter warnings → clean log + terminal
# stdbuf -oL forces line-buffered mode on each stage so output streams in real-time.
WARN_RE='\[WARNING\]: Found variable using reserved name: (name|tags)$'
export PYTHONUNBUFFERED=1
stdbuf -oL ansible-playbook "${PLAYBOOK}" "$@" 2>&1 \
    | stdbuf -oL tee -a "${LOG_FILE}" \
    | stdbuf -oL grep --line-buffered -Ev "${WARN_RE}" \
    | tee >(stdbuf -oL sed 's/\x1b\[[0-9;]*[mGKHF]//g; s/\x1b\[[0-9;]*[ABCD]//g' >> "${LOG_FILE_CLEAN}")
EXIT_CODE="${PIPESTATUS[0]}"

# ── Duration ──────────────────────────────────────────────────────────────────
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
END_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"

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
  Finished  : ${END_TIME}
  Duration  : ${DURATION_STR}
${STATUS_LINE}
  Log (ANSI): ${LOG_FILE}
  Log (text): ${LOG_FILE_CLEAN}
  HTML      : ${HTML_FILE}
================================================================
EOF
)
echo "${FOOTER}" | tee -a "${LOG_FILE}" | tee -a "${LOG_FILE_CLEAN}" > /dev/null
echo "${FOOTER}"

# ── Generate HTML report ──────────────────────────────────────────────────────
python3 - \
    "${LOG_FILE_CLEAN}" "${HTML_FILE}" \
    "${PLAYBOOK}" "${START_TIME}" "${END_TIME}" "${DURATION_STR}" \
    "${EXIT_CODE}" "$(whoami)@$(hostname)" "${ANSIBLE_DIR}" "${EXTRA_ARGS}" \
<<'PYEOF'
import sys, re, html as H, os

log_file   = sys.argv[1]
html_file  = sys.argv[2]
playbook   = sys.argv[3]
start_time = sys.argv[4]
end_time   = sys.argv[5]
duration   = sys.argv[6]
exit_code  = int(sys.argv[7])
user       = sys.argv[8]
workdir    = sys.argv[9]
extra_args = sys.argv[10] if len(sys.argv) > 10 else "(none)"

try:
    with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
        lines = [l.rstrip('\n') for l in f.readlines()]
except Exception as e:
    print(f"[html-report] Cannot read log file: {e}", file=sys.stderr)
    sys.exit(0)

# ── Parser ─────────────────────────────────────────────────────────────────────
plays = []
current_play = None
current_task = None
current_task_lines = []
recap_lines = []
in_recap = False

for line in lines:
    if re.match(r'^PLAY RECAP', line):
        if current_task is not None and current_play is not None:
            current_task['lines'] = current_task_lines[:]
            current_play['tasks'].append(current_task)
            current_task = None
            current_task_lines = []
        if current_play is not None:
            plays.append(current_play)
            current_play = None
        in_recap = True
        continue

    if in_recap:
        recap_lines.append(line)
        continue

    m = re.match(r'^PLAY \[(.+?)\]', line)
    if m:
        if current_task is not None and current_play is not None:
            current_task['lines'] = current_task_lines[:]
            current_play['tasks'].append(current_task)
            current_task = None
            current_task_lines = []
        if current_play is not None:
            plays.append(current_play)
        current_play = {'name': m.group(1), 'tasks': []}
        continue

    m = re.match(r'^(?:TASK|RUNNING HANDLER) \[(.+?)\]', line)
    if m and current_play is not None:
        if current_task is not None:
            current_task['lines'] = current_task_lines[:]
            current_play['tasks'].append(current_task)
        current_task = {'name': m.group(1), 'results': [], 'lines': []}
        current_task_lines = []
        continue

    if current_task is not None:
        current_task_lines.append(line)
        m2 = re.match(r'^(ok|changed|failed|fatal|skipping|unreachable|included|rescued|ignored): \[([^\]]+)\]', line)
        if m2:
            st = m2.group(1)
            host = m2.group(2)
            if st == 'skipping': st = 'skipped'
            if st == 'fatal':    st = 'failed'
            if not any(r['host'] == host and r['status'] == st for r in current_task['results']):
                current_task['results'].append({'status': st, 'host': host})

# ── Parse PLAY RECAP ───────────────────────────────────────────────────────────
recap_data = {}
for line in recap_lines:
    m = re.match(
        r'^(\S+)\s*:\s*ok=(\d+)\s+changed=(\d+)\s+unreachable=(\d+)\s+failed=(\d+)'
        r'\s+skipped=(\d+)\s+rescued=(\d+)\s+ignored=(\d+)',
        line
    )
    if m:
        recap_data[m.group(1)] = {
            'ok':          int(m.group(2)),
            'changed':     int(m.group(3)),
            'unreachable': int(m.group(4)),
            'failed':      int(m.group(5)),
            'skipped':     int(m.group(6)),
            'rescued':     int(m.group(7)),
            'ignored':     int(m.group(8)),
        }

# ── Aggregates ────────────────────────────────────────────────────────────────
status        = 'SUCCESS' if exit_code == 0 else 'FAILED'
total_ok      = sum(v['ok']                      for v in recap_data.values())
total_changed = sum(v['changed']                 for v in recap_data.values())
total_failed  = sum(v['failed'] + v['unreachable'] for v in recap_data.values())
total_skipped = sum(v['skipped']                 for v in recap_data.values())
total_tasks   = sum(len(p['tasks'])              for p in plays)
num_plays     = len(plays)

# Collect changed / failed tasks for the summary section
changed_rows_html = []
for play in plays:
    for task in play['tasks']:
        ch = [r['host'] for r in task['results'] if r['status'] == 'changed']
        fa = [r['host'] for r in task['results'] if r['status'] in ('failed', 'unreachable')]
        if ch:
            hosts_str = ', '.join(H.escape(h) for h in ch)
            changed_rows_html.append(
                f'<div class="row chg">'
                f'<span class="badge yel-b">CHANGED</span>'
                f'<span class="rdet">{H.escape(task["name"])}</span>'
                f'<span class="rhost-tag">{hosts_str}</span>'
                f'</div>'
            )
        if fa:
            hosts_str = ', '.join(H.escape(h) for h in fa)
            changed_rows_html.append(
                f'<div class="row fail">'
                f'<span class="badge red-b">FAILED</span>'
                f'<span class="rdet">{H.escape(task["name"])}</span>'
                f'<span class="rhost-tag">{hosts_str}</span>'
                f'</div>'
            )

if changed_rows_html:
    changes_section = f'''
<div class="section" style="margin-bottom:22px">
  <div class="sec-title">&#9998; Ce s-a modificat / aplicat</div>
  <div class="sec-body">
    {''.join(changed_rows_html)}
  </div>
</div>'''
else:
    changes_section = f'''
<div class="section" style="margin-bottom:22px">
  <div class="sec-title">&#9998; Ce s-a modificat / aplicat</div>
  <div class="sec-body">
    <div class="row info" style="padding:10px 18px;font-style:italic">Nicio modificare — totul era deja in starea dorita (idempotent).</div>
  </div>
</div>'''

# ── Build per-play sections ────────────────────────────────────────────────────
STATUS_ICON = {
    'ok':          '&#9679;',
    'changed':     '&#9650;',
    'failed':      '&#10007;',
    'unreachable': '&#10007;',
    'skipped':     '&#8212;',
    'included':    '&#8618;',
    'rescued':     '&#9733;',
    'ignored':     '&#126;',
}
STATUS_ROW_CLS = {
    'ok':          'ok',
    'changed':     'chg',
    'failed':      'fail',
    'unreachable': 'fail',
    'skipped':     'skip',
    'included':    'info',
    'rescued':     'info',
    'ignored':     'skip',
}

def host_badge_html(st, host):
    cls = {'ok': 'grn-b', 'changed': 'yel-b', 'failed': 'red-b',
           'unreachable': 'red-b', 'skipped': 'dim-b', 'included': 'blu-b',
           'rescued': 'pur-b', 'ignored': 'dim-b'}.get(st, 'dim-b')
    return f'<span class="badge {cls}">{H.escape(host)}</span>'

play_sections = []
for pi, play in enumerate(plays):
    task_rows = []
    for task in play['tasks']:
        results = task['results']
        statuses = [r['status'] for r in results]

        if 'failed' in statuses or 'unreachable' in statuses:
            row_cls = 'fail'
        elif 'changed' in statuses:
            row_cls = 'chg'
        elif statuses and all(s == 'skipped' for s in statuses):
            row_cls = 'skip'
        else:
            row_cls = 'ok'

        badges = ' '.join(host_badge_html(r['status'], r['host']) for r in results)
        if not badges:
            badges = '<span style="color:#3d444d">—</span>'

        raw_lines = [l for l in task['lines'] if l.strip()]
        if raw_lines:
            pre_content = H.escape('\n'.join(raw_lines))
            # Auto-expand if task failed/changed or output is substantial (>5 lines)
            auto_open = row_cls in ('fail', 'chg') or len(raw_lines) > 5
            open_attr = ' open' if auto_open else ''
            detail_html = (
                f'<details class="log-block"{open_attr}>'
                f'<summary>&#128196; output ({len(raw_lines)} linii)</summary>'
                f'<pre class="block-pre">{pre_content}</pre>'
                f'</details>'
            )
        else:
            detail_html = ''

        task_rows.append(
            f'<div class="trow {row_cls}">'
            f'<div class="trow-name">{H.escape(task["name"])}</div>'
            f'<div class="trow-badges">{badges}</div>'
            f'{detail_html}'
            f'</div>'
        )

    tc = len(play['tasks'])
    ch_count = sum(1 for t in play['tasks']
                   if any(r['status'] == 'changed' for r in t['results']))
    fa_count = sum(1 for t in play['tasks']
                   if any(r['status'] in ('failed','unreachable') for r in t['results']))

    badges_summary = ''
    if ch_count:
        badges_summary += f'<span class="badge yel-b">{ch_count} changed</span> '
    if fa_count:
        badges_summary += f'<span class="badge red-b">{fa_count} failed</span> '

    play_sections.append(f'''
<details class="section play-det" open>
  <summary class="sec-title play-sum">
    <span class="sec-arrow">&#9654;</span>
    <span style="flex:1">{H.escape(play["name"])}</span>
    {badges_summary}
    <span class="badge dim-b">{tc} task{"s" if tc != 1 else ""}</span>
  </summary>
  <div class="sec-body">
    {''.join(task_rows) if task_rows else '<div class="row info" style="padding:8px 18px">No tasks recorded.</div>'}
  </div>
</details>''')

plays_html = '\n'.join(play_sections)

# ── PLAY RECAP table ──────────────────────────────────────────────────────────
def recap_cell(val, color, zero_color='#3d444d'):
    c = color if val > 0 else zero_color
    w = 'font-weight:700;' if val > 0 else ''
    return f'<td style="text-align:center;color:{c};{w}">{val}</td>'

if recap_data:
    recap_rows = []
    for host, s in sorted(recap_data.items()):
        if s['failed'] > 0 or s['unreachable'] > 0:
            row_cls = 'fail'
        elif s['changed'] > 0:
            row_cls = 'chg'
        else:
            row_cls = 'ok'
        recap_rows.append(
            f'<tr class="rrow {row_cls}">'
            f'<td class="rhost-cell">{H.escape(host)}</td>'
            + recap_cell(s['ok'],          '#3fb950')
            + recap_cell(s['changed'],     '#d29922')
            + recap_cell(s['unreachable'], '#f85149')
            + recap_cell(s['failed'],      '#f85149')
            + recap_cell(s['skipped'],     '#8b949e')
            + recap_cell(s['rescued'],     '#bc8cff')
            + recap_cell(s['ignored'],     '#8b949e')
            + '</tr>'
        )
    recap_html = f'''
<div class="section" style="margin-top:26px">
  <div class="sec-title">&#9646;&#9646; PLAY RECAP</div>
  <div class="sec-body" style="padding:0">
    <table class="rtable">
      <thead><tr>
        <th style="text-align:left">Host</th>
        <th>ok</th><th>changed</th><th>unreachable</th>
        <th>failed</th><th>skipped</th><th>rescued</th><th>ignored</th>
      </tr></thead>
      <tbody>{''.join(recap_rows)}</tbody>
    </table>
  </div>
</div>'''
else:
    recap_html = ''

# ── Stats boxes ───────────────────────────────────────────────────────────────
def stat_box(n, label, color, bg):
    return (f'<div class="stat" style="border-color:{color}">'
            f'<div class="stat-n" style="color:{color}">{n}</div>'
            f'<div class="stat-l">{label}</div>'
            f'</div>')

stats_html = (
    stat_box(total_ok,      'ok',             '#3fb950', 'rgba(63,185,80,.08)') +
    stat_box(total_changed, 'changed',        '#d29922', 'rgba(210,153,34,.08)') +
    stat_box(total_failed,  'failed',         '#f85149', 'rgba(248,81,73,.08)') +
    stat_box(total_skipped, 'skipped',        '#8b949e', 'rgba(139,148,158,.06)') +
    stat_box(total_tasks,   'total tasks',    '#58a6ff', 'rgba(88,166,255,.06)') +
    stat_box(num_plays,     'plays',          '#79c0ff', 'rgba(121,192,255,.06)')
)

# ── Banner ────────────────────────────────────────────────────────────────────
banner_cls  = 'ok'  if exit_code == 0 else 'fail'
banner_icon = '&#10003;' if exit_code == 0 else '&#10007;'
banner_txt  = 'EXECUȚIE REUȘITĂ — Toate taskurile au trecut' if exit_code == 0 \
              else f'EXECUȚIE EȘUATĂ — exit code {exit_code}'

# ── Playbook short name ───────────────────────────────────────────────────────
playbook_short = os.path.basename(playbook)

# ── Final HTML ────────────────────────────────────────────────────────────────
HTML = f'''<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ansible — {H.escape(playbook_short)} — SC MEDIA SRL</title>
<style>
:root{{--bg:#0d1117;--bg2:#161b22;--bg3:#21262d;--bdr:#30363d;--txt:#c9d1d9;--muted:#8b949e;
      --blue:#58a6ff;--green:#3fb950;--yel:#d29922;--red:#f85149;--cyan:#39c5cf;--pur:#bc8cff;}}
*{{box-sizing:border-box;margin:0;padding:0;}}
body{{font-family:'Segoe UI',Consolas,monospace;background:var(--bg);color:var(--txt);
      padding:24px;line-height:1.55;}}
.wrap{{max-width:1100px;margin:0 auto;}}

/* header card */
.hcard{{background:linear-gradient(135deg,#0d1117,#161b22);border:1px solid var(--bdr);
        border-top:3px solid var(--cyan);border-radius:8px;padding:28px 32px;margin-bottom:18px;}}
.hcard h1{{color:var(--cyan);font-size:1.4em;margin-bottom:6px;}}
.hcard .sub{{color:var(--muted);font-size:.83em;margin-bottom:14px;}}
.meta{{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px 24px;}}
.meta-i{{font-size:.81em;color:var(--muted);}}
.meta-i strong{{color:var(--txt);font-family:Consolas,monospace;}}

/* banner */
.banner{{text-align:center;padding:11px 20px;border-radius:6px;font-weight:700;
         font-size:.95em;letter-spacing:1.2px;margin-bottom:18px;text-transform:uppercase;}}
.banner.ok  {{background:rgba(63,185,80,.12); border:1px solid var(--green);color:var(--green);}}
.banner.fail{{background:rgba(248,81,73,.12); border:1px solid var(--red);  color:var(--red);}}

/* stats boxes */
.stats{{display:flex;gap:12px;margin-bottom:20px;flex-wrap:wrap;}}
.stat{{flex:1;min-width:100px;background:var(--bg2);border:1px solid var(--bdr);
       border-radius:8px;padding:16px 12px;text-align:center;}}
.stat-n{{font-size:2.2em;font-weight:700;line-height:1;}}
.stat-l{{font-size:.7em;color:var(--muted);margin-top:5px;text-transform:uppercase;letter-spacing:.5px;}}

/* sections */
.section{{background:var(--bg2);border:1px solid var(--bdr);border-radius:8px;
          margin-bottom:12px;overflow:hidden;}}
.sec-title{{background:var(--bg3);padding:9px 18px;font-weight:600;color:var(--cyan);
            font-size:.88em;letter-spacing:.3px;border-bottom:1px solid var(--bdr);
            display:flex;align-items:center;gap:8px;}}
.sec-body{{padding:6px 0;}}

/* play details */
details.play-det{{background:var(--bg2);border:1px solid var(--bdr);border-radius:8px;
                  margin-bottom:12px;overflow:hidden;}}
details.play-det>summary{{list-style:none;cursor:pointer;user-select:none;}}
details.play-det>summary::-webkit-details-marker{{display:none;}}
.play-sum{{background:var(--bg3);padding:9px 18px;font-weight:600;color:var(--cyan);
           font-size:.88em;letter-spacing:.3px;border-bottom:1px solid var(--bdr);}}
.play-sum:hover{{background:#2c333b;}}
.sec-arrow{{font-size:.68em;color:var(--muted);transition:transform .15s;flex-shrink:0;}}
details[open]>.play-sum .sec-arrow{{transform:rotate(90deg);}}

/* task rows */
.trow{{padding:5px 18px 5px 15px;border-left:3px solid transparent;
       display:flex;flex-direction:column;gap:3px;font-size:.86em;
       border-bottom:1px solid rgba(48,54,61,.5);}}
.trow:last-child{{border-bottom:none;}}
.trow.ok  {{border-left-color:var(--green);}}
.trow.chg {{border-left-color:var(--yel);background:rgba(210,153,34,.04);}}
.trow.fail{{border-left-color:var(--red); background:rgba(248,81,73,.06);}}
.trow.skip{{border-left-color:#3d444d;opacity:.55;}}
.trow.info{{border-left-color:var(--blue);}}
.trow-name{{color:var(--txt);font-family:Consolas,monospace;font-size:.84em;padding-top:2px;}}
.trow-badges{{display:flex;flex-wrap:wrap;gap:4px;}}

/* rows (changes summary) */
.row{{display:flex;align-items:baseline;gap:8px;padding:4px 18px;font-size:.86em;
      border-bottom:1px solid rgba(48,54,61,.4);}}
.row:last-child{{border-bottom:none;}}
.row.ok  {{color:var(--green);}}
.row.chg {{color:var(--yel); background:rgba(210,153,34,.05);border-left:3px solid var(--yel);padding-left:15px;}}
.row.fail{{color:var(--red);  background:rgba(248,81,73,.06); border-left:3px solid var(--red); padding-left:15px;}}
.row.info{{color:var(--muted);}}
.rdet{{flex:1;color:var(--txt);font-family:Consolas,monospace;font-size:.84em;}}
.rhost-tag{{font-size:.8em;color:var(--muted);white-space:nowrap;}}

/* badges */
.badge{{display:inline-block;padding:2px 8px;border-radius:20px;font-size:.72em;font-weight:700;
        text-transform:uppercase;letter-spacing:.4px;flex-shrink:0;white-space:nowrap;}}
.grn-b{{background:rgba(63,185,80,.18); color:var(--green);border:1px solid var(--green);}}
.yel-b{{background:rgba(210,153,34,.18);color:var(--yel);  border:1px solid var(--yel);}}
.red-b{{background:rgba(248,81,73,.18); color:var(--red);  border:1px solid var(--red);}}
.blu-b{{background:rgba(88,166,255,.18);color:var(--blue); border:1px solid var(--blue);}}
.dim-b{{background:rgba(139,148,158,.12);color:var(--muted);border:1px solid #3d444d;}}
.pur-b{{background:rgba(188,140,255,.18);color:var(--pur); border:1px solid var(--pur);}}

/* log block */
details.log-block{{margin:4px 0;}}
details.log-block>summary{{display:flex;gap:7px;align-items:center;padding:4px 0;cursor:pointer;
  font-size:.82em;color:var(--blue);list-style:none;user-select:none;}}
details.log-block>summary::-webkit-details-marker{{display:none;}}
details.log-block>summary::before{{content:'&#9654;';font-size:.65em;color:var(--muted);
  transition:transform .15s;flex-shrink:0;}}
details.log-block[open]>summary::before{{transform:rotate(90deg);}}
details.log-block>summary:hover{{color:var(--cyan);}}
.block-pre{{background:#010409;border:1px solid var(--bdr);padding:10px 16px;
  border-radius:0 0 4px 4px;font-family:Consolas,monospace;font-size:.75em;
  color:#8b949e;white-space:pre-wrap;word-break:break-word;
  max-height:440px;overflow-y:auto;border-left:3px solid var(--blue);}}

/* recap table */
.rtable{{width:100%;border-collapse:collapse;font-size:.86em;}}
.rtable thead tr{{background:var(--bg3);color:var(--muted);font-size:.75em;text-transform:uppercase;}}
.rtable th{{padding:8px 16px;border-bottom:1px solid var(--bdr);}}
.rtable td{{padding:8px 16px;border-bottom:1px solid #1c2128;}}
.rtable tr:last-child td{{border-bottom:none;}}
.rrow.ok  {{border-left:3px solid var(--green);}}
.rrow.chg {{border-left:3px solid var(--yel);}}
.rrow.fail{{border-left:3px solid var(--red);background:rgba(248,81,73,.05);}}
.rhost-cell{{font-family:Consolas,monospace;color:var(--txt);font-weight:600;}}

/* footer */
.footer{{text-align:center;color:var(--muted);font-size:.73em;margin-top:28px;
         padding-top:14px;border-top:1px solid var(--bdr);}}
.footer strong{{color:var(--cyan);}}

/* scrollbar */
::-webkit-scrollbar{{width:6px;height:6px;}}
::-webkit-scrollbar-track{{background:var(--bg);}}
::-webkit-scrollbar-thumb{{background:var(--bdr);border-radius:3px;}}
::-webkit-scrollbar-thumb:hover{{background:var(--muted);}}

@media(max-width:700px){{
  .stats{{flex-direction:column;}}
  .meta{{grid-template-columns:1fr;}}
}}
</style>
</head>
<body>
<div class="wrap">

<!-- Header card -->
<div class="hcard">
  <h1>SC MEDIA SRL &mdash; Ansible: {H.escape(playbook_short)}</h1>
  <p class="sub">Log de execuție generat automat &middot; Proiect disertație master</p>
  <div class="meta">
    <div class="meta-i">Playbook: <strong>{H.escape(playbook)}</strong></div>
    <div class="meta-i">Început: <strong>{H.escape(start_time)}</strong></div>
    <div class="meta-i">Terminat: <strong>{H.escape(end_time)}</strong></div>
    <div class="meta-i">Durată: <strong>{H.escape(duration)}</strong></div>
    <div class="meta-i">Utilizator: <strong>{H.escape(user)}</strong></div>
    <div class="meta-i">Extra args: <strong>{H.escape(extra_args)}</strong></div>
  </div>
</div>

<!-- Status banner -->
<div class="banner {banner_cls}">{banner_icon} &nbsp; {H.escape(banner_txt)}</div>

<!-- Stats boxes -->
<div class="stats">
  {stats_html}
</div>

<!-- Changes summary -->
{changes_section}

<!-- Per-play execution detail -->
<div style="font-size:.78rem;text-transform:uppercase;letter-spacing:.1em;
            color:var(--muted);margin-bottom:10px;padding-bottom:5px;
            border-bottom:1px solid #21262d;">
  &#9654; Detaliu execuție — {num_plays} play{"s" if num_plays != 1 else ""}
</div>
{plays_html}

<!-- PLAY RECAP -->
{recap_html}

<!-- Footer -->
<div class="footer">
  Generat de <strong>run-playbook.sh</strong> &mdash;
  <strong>SC IT SECURITY SRL</strong> &mdash; {H.escape(end_time)}
</div>

</div>
</body>
</html>'''

try:
    with open(html_file, 'w', encoding='utf-8') as f:
        f.write(HTML)
    print(f"[html-report] {html_file}")
except Exception as e:
    print(f"[html-report] Write failed: {e}", file=sys.stderr)

PYEOF

exit "${EXIT_CODE}"
