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
ansible-playbook "${PLAYBOOK}" "$@" 2>&1 \
    | tee >(strip_ansi >> "${LOG_FILE_CLEAN}") \
    | tee -a "${LOG_FILE}"
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
import sys
import re
import html as H
import os

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
        m = re.match(r'^(ok|changed|failed|fatal|skipping|unreachable|included|rescued|ignored): \[([^\]]+)\]', line)
        if m:
            st = m.group(1)
            host = m.group(2)
            if st == 'skipping': st = 'skipped'
            if st == 'fatal': st = 'failed'
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

# ── Aggregate totals ───────────────────────────────────────────────────────────
status        = 'SUCCESS' if exit_code == 0 else 'FAILED'
status_color  = '#2ea043' if exit_code == 0 else '#da3633'
total_ok      = sum(v['ok']          for v in recap_data.values())
total_changed = sum(v['changed']     for v in recap_data.values())
total_failed  = sum(v['failed'] + v['unreachable'] for v in recap_data.values())
total_skipped = sum(v['skipped']     for v in recap_data.values())
total_tasks   = sum(len(p['tasks'])  for p in plays)

# ── Color map ──────────────────────────────────────────────────────────────────
COLORS = {
    'ok':          ('#2ea043', '#fff'),
    'changed':     ('#d29922', '#fff'),
    'failed':      ('#da3633', '#fff'),
    'unreachable': ('#b91c1c', '#fff'),
    'skipped':     ('#6e7681', '#fff'),
    'included':    ('#2d7dd2', '#fff'),
    'rescued':     ('#8957e5', '#fff'),
    'ignored':     ('#6e7681', '#fff'),
}

def host_badge(st, host):
    bg, fg = COLORS.get(st, ('#555', '#fff'))
    return (f'<span class="hbadge" style="background:{bg};color:{fg}">'
            f'{H.escape(host)}: {H.escape(st)}</span>')

def task_row_class(results):
    statuses = [r['status'] for r in results]
    if 'failed' in statuses or 'unreachable' in statuses: return 'tr-failed'
    if 'changed' in statuses:                              return 'tr-changed'
    if statuses and all(s == 'skipped' for s in statuses): return 'tr-skipped'
    return 'tr-ok'

def recap_td(val, key):
    if val == 0:
        return f'<td class="rz">{val}</td>'
    bg, fg = COLORS.get(key, ('#555', '#fff'))
    return f'<td class="rnz" style="background:{bg};color:{fg}">{val}</td>'

# ── Build plays HTML ───────────────────────────────────────────────────────────
plays_html_parts = []
for play in plays:
    rows = []
    for task in play['tasks']:
        badges = ' '.join(host_badge(r['status'], r['host']) for r in task['results'])
        if not badges:
            badges = '<span class="no-result">—</span>'

        row_cls = task_row_class(task['results'])

        raw_lines = [l for l in task['lines'] if l.strip()]
        if raw_lines:
            raw_html = H.escape('\n'.join(raw_lines))
            detail = (f'<details class="tdet"><summary>Show output</summary>'
                      f'<pre class="tout">{raw_html}</pre></details>')
        else:
            detail = ''

        rows.append(
            f'<tr class="{row_cls}">'
            f'<td class="tname">{H.escape(task["name"])}</td>'
            f'<td class="tres">{badges}</td>'
            f'<td class="tdet-col">{detail}</td>'
            f'</tr>'
        )

    tbody = '\n'.join(rows) if rows else '<tr><td colspan="3" class="no-result">No tasks recorded</td></tr>'
    tc = len(play['tasks'])
    plays_html_parts.append(f'''
<details class="play" open>
  <summary>
    <span class="play-arrow">▶</span>
    <span class="play-name">{H.escape(play["name"])}</span>
    <span class="play-count">{tc} task{"s" if tc != 1 else ""}</span>
  </summary>
  <table class="ttable">
    <thead><tr><th>Task</th><th>Result per host</th><th>Output</th></tr></thead>
    <tbody>{tbody}</tbody>
  </table>
</details>''')

plays_html = '\n'.join(plays_html_parts)

# ── Build recap HTML ───────────────────────────────────────────────────────────
if recap_data:
    recap_rows = []
    for host, s in sorted(recap_data.items()):
        if s['failed'] > 0 or s['unreachable'] > 0:
            hcls = 'rh-failed'
        elif s['changed'] > 0:
            hcls = 'rh-changed'
        else:
            hcls = 'rh-ok'
        recap_rows.append(
            f'<tr class="{hcls}">'
            f'<td class="rhost">{H.escape(host)}</td>'
            f'{recap_td(s["ok"], "ok")}'
            f'{recap_td(s["changed"], "changed")}'
            f'{recap_td(s["unreachable"], "unreachable")}'
            f'{recap_td(s["failed"], "failed")}'
            f'{recap_td(s["skipped"], "skipped")}'
            f'{recap_td(s["rescued"], "rescued")}'
            f'{recap_td(s["ignored"], "ignored")}'
            f'</tr>'
        )
    recap_html = f'''
<section class="recap">
  <h2 class="recap-title">PLAY RECAP</h2>
  <table class="rtable">
    <thead><tr>
      <th>Host</th><th>ok</th><th>changed</th><th>unreachable</th>
      <th>failed</th><th>skipped</th><th>rescued</th><th>ignored</th>
    </tr></thead>
    <tbody>{"".join(recap_rows)}</tbody>
  </table>
</section>'''
else:
    recap_html = ''

# ── Assemble HTML ──────────────────────────────────────────────────────────────
playbook_short = os.path.basename(playbook)
icon = '✓' if exit_code == 0 else '✗'

HTML = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ansible — {H.escape(playbook_short)}</title>
<style>
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:"Segoe UI",system-ui,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;padding-bottom:60px}}

/* top bar */
.topbar{{background:{status_color};color:#fff;padding:12px 24px;display:flex;align-items:center;gap:14px;
         position:sticky;top:0;z-index:99;box-shadow:0 2px 10px rgba(0,0,0,.5)}}
.topbar-icon{{font-size:1.5rem;font-weight:700}}
.topbar-title{{flex:1;font-size:1.1rem;font-weight:700;letter-spacing:.03em}}
.topbar-dur{{font-size:.9rem;opacity:.85}}

/* container */
.wrap{{max-width:1260px;margin:0 auto;padding:28px 18px}}

/* meta card */
.meta{{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:20px 24px;
       margin-bottom:22px;display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px 28px}}
.ml{{font-size:.72rem;color:#8b949e;text-transform:uppercase;letter-spacing:.09em;margin-bottom:3px}}
.mv{{font-size:.9rem;color:#e6edf3;font-family:"Consolas","Courier New",monospace;word-break:break-all}}
.mv.status-ok{{color:{status_color};font-weight:700}}

/* stats strip */
.stats{{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:26px}}
.chip{{padding:6px 18px;border-radius:20px;font-size:.88rem;font-weight:600;display:flex;gap:7px;align-items:center}}
.chip-lbl{{font-weight:400;opacity:.8}}

/* section heading */
.sh{{font-size:.78rem;text-transform:uppercase;letter-spacing:.1em;color:#8b949e;
     margin:0 0 12px;padding-bottom:5px;border-bottom:1px solid #21262d}}

/* play accordion */
.play{{background:#161b22;border:1px solid #30363d;border-radius:9px;margin-bottom:14px;overflow:hidden}}
.play>summary{{list-style:none;cursor:pointer;padding:13px 20px;background:#1c2128;
               display:flex;align-items:center;gap:12px;user-select:none}}
.play>summary::-webkit-details-marker{{display:none}}
.play-arrow{{color:#58a6ff;font-size:.7rem;transition:transform .2s;flex-shrink:0}}
.play[open]>.play>summary .play-arrow,
.play[open]>summary .play-arrow{{transform:rotate(90deg)}}
.play-name{{font-size:.98rem;font-weight:600;color:#58a6ff;flex:1}}
.play-count{{font-size:.78rem;color:#8b949e;background:#21262d;padding:2px 10px;border-radius:12px}}

/* task table */
.ttable{{width:100%;border-collapse:collapse;font-size:.85rem}}
.ttable thead tr{{background:#21262d;color:#8b949e;font-size:.75rem;text-transform:uppercase;letter-spacing:.05em}}
.ttable th{{padding:7px 16px;text-align:left;border-bottom:1px solid #30363d;white-space:nowrap}}
.ttable td{{padding:8px 16px;border-bottom:1px solid #1c2128;vertical-align:top}}
.ttable tr:last-child td{{border-bottom:none}}
.tr-ok     {{border-left:3px solid #2ea043}}
.tr-changed{{border-left:3px solid #d29922}}
.tr-failed {{border-left:3px solid #da3633;background:#160808}}
.tr-skipped{{border-left:3px solid #6e7681;opacity:.6}}
.tname{{color:#e6edf3;font-family:"Consolas",monospace;font-size:.82rem;max-width:360px;word-break:break-word}}
.tres{{white-space:normal}}
.no-result{{color:#484f58;font-size:.82rem;font-style:italic}}

/* host badges */
.hbadge{{display:inline-block;padding:3px 10px;border-radius:14px;font-size:.78rem;font-weight:600;
         margin:2px 3px 2px 0;white-space:nowrap}}

/* task detail */
.tdet>summary{{list-style:none;cursor:pointer;color:#58a6ff;font-size:.78rem;user-select:none;white-space:nowrap}}
.tdet>summary::-webkit-details-marker{{display:none}}
.tout{{margin-top:8px;background:#0d1117;border:1px solid #30363d;border-radius:6px;padding:12px;
       font-family:"Consolas","Courier New",monospace;font-size:.76rem;color:#c9d1d9;
       white-space:pre-wrap;word-break:break-word;max-height:420px;overflow-y:auto;line-height:1.5}}

/* recap */
.recap{{background:#161b22;border:1px solid #30363d;border-radius:9px;overflow:hidden;margin-top:26px}}
.recap-title{{padding:13px 20px;background:#1c2128;font-size:.9rem;font-weight:700;
              letter-spacing:.05em;border-bottom:1px solid #30363d}}
.rtable{{width:100%;border-collapse:collapse;font-size:.86rem}}
.rtable thead tr{{background:#21262d;color:#8b949e;font-size:.75rem;text-transform:uppercase}}
.rtable th{{padding:8px 16px;text-align:center;border-bottom:1px solid #30363d}}
.rtable th:first-child{{text-align:left}}
.rtable td{{padding:9px 16px;text-align:center;border-bottom:1px solid #1c2128}}
.rtable tr:last-child td{{border-bottom:none}}
.rhost{{text-align:left!important;font-family:monospace;color:#e6edf3;font-weight:600}}
.rz{{color:#484f58}}
.rnz{{font-weight:700;border-radius:4px}}
.rh-ok{{border-left:3px solid #2ea043}}
.rh-changed{{border-left:3px solid #d29922}}
.rh-failed{{border-left:3px solid #da3633;background:#160808}}

/* footer */
.foot{{text-align:center;color:#484f58;font-size:.76rem;margin-top:44px}}
</style>
</head>
<body>

<div class="topbar">
  <span class="topbar-icon">{icon}</span>
  <span class="topbar-title">Ansible &mdash; {H.escape(playbook_short)}</span>
  <span class="topbar-dur">{H.escape(duration)}</span>
</div>

<div class="wrap">

  <!-- Metadata -->
  <div class="meta">
    <div><div class="ml">Playbook</div><div class="mv">{H.escape(playbook)}</div></div>
    <div><div class="ml">Status</div><div class="mv status-ok">{H.escape(status)}</div></div>
    <div><div class="ml">Started</div><div class="mv">{H.escape(start_time)}</div></div>
    <div><div class="ml">Finished</div><div class="mv">{H.escape(end_time)}</div></div>
    <div><div class="ml">Duration</div><div class="mv">{H.escape(duration)}</div></div>
    <div><div class="ml">User</div><div class="mv">{H.escape(user)}</div></div>
    <div><div class="ml">Directory</div><div class="mv">{H.escape(workdir)}</div></div>
    <div><div class="ml">Extra args</div><div class="mv">{H.escape(extra_args)}</div></div>
  </div>

  <!-- Stats -->
  <div class="stats">
    <div class="chip" style="background:#0d2a0d;color:#2ea043">
      <span>{total_ok}</span><span class="chip-lbl">ok</span>
    </div>
    <div class="chip" style="background:#2a1f00;color:#d29922">
      <span>{total_changed}</span><span class="chip-lbl">changed</span>
    </div>
    <div class="chip" style="background:#2a0808;color:#da3633">
      <span>{total_failed}</span><span class="chip-lbl">failed / unreachable</span>
    </div>
    <div class="chip" style="background:#161b22;color:#6e7681">
      <span>{total_skipped}</span><span class="chip-lbl">skipped</span>
    </div>
    <div class="chip" style="background:#0c1929;color:#58a6ff">
      <span>{total_tasks}</span><span class="chip-lbl">tasks</span>
    </div>
    <div class="chip" style="background:#0c1929;color:#79c0ff">
      <span>{len(plays)}</span><span class="chip-lbl">plays</span>
    </div>
  </div>

  <!-- Plays -->
  <p class="sh">Execution detail</p>
  {plays_html}

  <!-- Recap -->
  {recap_html}

  <div class="foot">
    Generated by run-playbook.sh &mdash; SC IT SECURITY SRL &mdash; {H.escape(end_time)}
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
