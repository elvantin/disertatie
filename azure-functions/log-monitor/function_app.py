"""
Azure Function: Log Monitor cu AI — SC MEDIA SRL
=================================================
Timer trigger la fiecare 15 minute.

Flow:
  1. Interogheaza Log Analytics cu KQL (heartbeat, erori, securitate, perf)
  2. Trimite datele catre Azure OpenAI GPT-4o pentru analiza
  3. Logheaza rezultatele structurat in Application Insights
     (vizualizare in Azure Portal -> appi-mediasrl-logmonitor -> Logs)

Autentificare: Managed Identity (fara chei hardcodate).
  - MI -> Log Analytics Reader  (query KQL)
  - MI -> Cognitive Services OpenAI User  (apeluri GPT-4o)
"""

import azure.functions as func
import logging
import json
import os
from datetime import datetime, timedelta, timezone

from azure.identity import ManagedIdentityCredential, DefaultAzureCredential, get_bearer_token_provider
from azure.monitor.query import LogsQueryClient, LogsQueryStatus
from openai import AzureOpenAI

# ============================================================
# Configuratie din App Settings
# ============================================================

WORKSPACE_ID      = os.environ["LOG_ANALYTICS_WORKSPACE_ID"]   # GUID workspace
AOAI_ENDPOINT     = os.environ["AOAI_ENDPOINT"]                 # https://aoai-mediasrl-productie.openai.azure.com/
AOAI_DEPLOYMENT   = os.environ.get("AOAI_DEPLOYMENT_NAME", "gpt4o")
EXPECTED_VMS      = os.environ.get("EXPECTED_VMS",
                    "vm-jmp-01,vm-web-01,vm-app-01,vm-cms-01,vm-db-01,vm-fs-01").split(",")
QUERY_WINDOW_MIN  = int(os.environ.get("QUERY_WINDOW_MINUTES", "15"))

# ============================================================
# System Prompt pentru GPT-4o
# ============================================================

SYSTEM_PROMPT = """Ești un expert în monitorizarea infrastructurii Azure pentru SC MEDIA SRL.
Analizezi date de logare din Log Analytics și identifici probleme, anomalii și riscuri de securitate.

Infrastructura monitorizată:
- vm-jmp-01  : Ubuntu 22.04, Jumphost + Ansible controller  (subnet: snet-mgmt, 10.10.12.0/24)
- vm-web-01  : Ubuntu 22.04, Nginx reverse proxy + SSL      (subnet: snet-prod, 10.10.10.0/24)
- vm-app-01  : Ubuntu 22.04, Node.js REST API :8080         (subnet: snet-prod)
- vm-cms-01  : Ubuntu 22.04, WordPress + PHP-FPM            (subnet: snet-prod)
- vm-db-01   : Windows Server 2022, MySQL 8.0 :3306         (subnet: snet-prod)
- vm-fs-01   : Windows Server 2022, SMB File Server         (subnet: snet-prod)

Reguli de clasificare severitate:
- CRITICAL : VM offline, eroare de securitate activa (brute-force reusit, intruziune), serviciu critic cazut
- WARNING  : VM nu a raportat heartbeat recent, erori repetate, tentative brute-force, CPU/RAM ridicat
- INFO     : Informatii de rutina, upgrade-uri, reconectari normale

Raspunde EXCLUSIV cu un obiect JSON valid (fara markdown, fara text extra) cu aceasta structura:
{
  "overall_status": "CRITICAL|WARNING|OK",
  "summary": "Rezumat in romana, max 2 propozitii",
  "vm_status": {
    "vm-jmp-01": "ONLINE|OFFLINE|UNKNOWN",
    "vm-web-01": "ONLINE|OFFLINE|UNKNOWN",
    "vm-app-01": "ONLINE|OFFLINE|UNKNOWN",
    "vm-cms-01": "ONLINE|OFFLINE|UNKNOWN",
    "vm-db-01":  "ONLINE|OFFLINE|UNKNOWN",
    "vm-fs-01":  "ONLINE|OFFLINE|UNKNOWN"
  },
  "issues": [
    {
      "severity": "CRITICAL|WARNING|INFO",
      "vm": "nume_vm sau 'infrastructure'",
      "type": "VM_OFFLINE|SECURITY_ALERT|SERVICE_ERROR|PERFORMANCE|INFO",
      "description": "Descriere clara a problemei",
      "recommendation": "Actiune concreta recomandata"
    }
  ],
  "security_summary": "Rezumat securitate (tentative login, anomalii)",
  "recommendations": ["Recomandare 1", "Recomandare 2"]
}"""

# ============================================================
# Azure Function App
# ============================================================

app = func.FunctionApp()


@app.timer_trigger(
    schedule="0 */15 * * * *",   # La fiecare 15 minute
    arg_name="myTimer",
    run_on_startup=False,
    use_monitor=True
)
def log_monitor(myTimer: func.TimerRequest) -> None:
    utc_now = datetime.now(timezone.utc)
    logging.info("=" * 60)
    logging.info(f"[LogMonitor] Pornit la {utc_now.strftime('%Y-%m-%d %H:%M:%S')} UTC")
    if myTimer.past_due:
        logging.warning("[LogMonitor] Timer-ul a intarziat fata de schedule!")

    # ----------------------------------------------------------
    # Credential: Managed Identity in Azure, DefaultAzureCredential local
    # ----------------------------------------------------------
    try:
        credential = ManagedIdentityCredential()
        # Test rapid ca credentialul functioneaza
        credential.get_token("https://management.azure.com/.default")
        logging.info("[LogMonitor] Autentificare: Managed Identity")
    except Exception:
        credential = DefaultAzureCredential()
        logging.info("[LogMonitor] Autentificare: DefaultAzureCredential (local dev)")

    # ----------------------------------------------------------
    # STEP 1: Colecteaza date din Log Analytics
    # ----------------------------------------------------------
    log_data = _collect_log_data(credential, utc_now)

    # ----------------------------------------------------------
    # STEP 2: Analiza cu GPT-4o
    # ----------------------------------------------------------
    analysis = _analyze_with_gpt4o(credential, log_data, utc_now)

    # ----------------------------------------------------------
    # STEP 3: Logheaza rezultatele in Application Insights
    # ----------------------------------------------------------
    _emit_results(analysis, utc_now)

    logging.info("[LogMonitor] Ciclu complet.")


# ============================================================
# STEP 1: Colectare date Log Analytics
# ============================================================

def _collect_log_data(credential, utc_now: datetime) -> dict:
    """Executa query-urile KQL si returneaza datele colectate."""
    logs_client = LogsQueryClient(credential)
    timespan = timedelta(minutes=QUERY_WINDOW_MIN)

    kql_queries = {
        "heartbeat": f"""
            Heartbeat
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | summarize LastHeartbeat = max(TimeGenerated), Count = count() by Computer
            | extend MinutesAgo = datetime_diff('minute', now(), LastHeartbeat)
            | extend Status = iff(MinutesAgo > 10, 'OFFLINE', 'ONLINE')
            | project Computer, Status, MinutesAgo
        """,
        "syslog_errors": f"""
            Syslog
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | where SeverityLevel in~ ('err', 'crit', 'alert', 'emerg')
            | project TimeGenerated, Computer, SeverityLevel, SyslogMessage
            | order by TimeGenerated desc
            | limit 30
        """,
        "windows_events": f"""
            Event
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | where EventLevelName in ('Error', 'Critical')
            | project TimeGenerated, Computer, EventLog, EventID, EventLevelName, RenderedDescription
            | order by TimeGenerated desc
            | limit 30
        """,
        "failed_logins": f"""
            Syslog
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | where SyslogMessage contains 'Failed password'
                or SyslogMessage contains 'Invalid user'
                or SyslogMessage contains 'authentication failure'
            | summarize Attempts = count(),
                        Sources = make_set(extract(@'from ([\d\.]+)', 1, SyslogMessage), 10)
              by Computer
            | order by Attempts desc
        """,
        "cpu_usage": f"""
            Perf
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | where CounterName == '% Processor Time' and InstanceName == '_Total'
            | summarize AvgCPU = round(avg(CounterValue), 1),
                        MaxCPU = round(max(CounterValue), 1)
              by Computer
            | order by AvgCPU desc
        """,
        "memory_available": f"""
            Perf
            | where TimeGenerated > ago({QUERY_WINDOW_MIN}m)
            | where CounterName == 'Available MBytes'
            | summarize AvgMB = round(avg(CounterValue), 0),
                        MinMB = round(min(CounterValue), 0)
              by Computer
        """,
    }

    log_data = {}
    for name, query in kql_queries.items():
        rows = _run_kql(logs_client, WORKSPACE_ID, query, timespan)
        log_data[name] = rows
        logging.info(f"[LogMonitor] KQL '{name}': {len(rows)} randuri")

    # VM-uri care lipsesc complet din heartbeat
    reporting = {r["Computer"] for r in log_data.get("heartbeat", [])}
    missing = [vm for vm in EXPECTED_VMS if not any(vm in c for c in reporting)]
    if missing:
        log_data["missing_from_heartbeat"] = missing
        logging.warning(f"[LogMonitor] VM-uri fara heartbeat: {missing}")

    return log_data


def _run_kql(client: LogsQueryClient, workspace_id: str, query: str, timespan: timedelta) -> list:
    """Executa un query KQL si returneaza lista de dictionare."""
    try:
        resp = client.query_workspace(workspace_id, query, timespan=timespan)
        if resp.status == LogsQueryStatus.SUCCESS and resp.tables:
            table = resp.tables[0]
            cols = [c.name for c in table.columns]
            return [dict(zip(cols, row)) for row in table.rows]
    except Exception as ex:
        logging.warning(f"[LogMonitor] KQL error: {ex}")
    return []


# ============================================================
# STEP 2: Analiza GPT-4o
# ============================================================

def _analyze_with_gpt4o(credential, log_data: dict, utc_now: datetime) -> dict:
    """Trimite datele catre GPT-4o si returneaza analiza JSON."""

    token_provider = get_bearer_token_provider(
        credential, "https://cognitiveservices.azure.com/.default"
    )
    client = AzureOpenAI(
        azure_endpoint=AOAI_ENDPOINT,
        azure_ad_token_provider=token_provider,
        api_version="2024-08-01-preview",
    )

    data_str = json.dumps(log_data, default=str, ensure_ascii=False, indent=2)
    # Trunchiem daca depasim ~50k caractere (context window safety)
    if len(data_str) > 50_000:
        data_str = data_str[:50_000] + "\n... [date trunchiate]"

    user_msg = (
        f"Analizeaza datele de monitorizare pentru ultimele {QUERY_WINDOW_MIN} minute "
        f"(timestamp: {utc_now.isoformat()}).\n\n"
        f"VM-uri asteptate sa fie online: {', '.join(EXPECTED_VMS)}\n\n"
        f"DATE LOG ANALYTICS:\n{data_str}"
    )

    try:
        resp = client.chat.completions.create(
            model=AOAI_DEPLOYMENT,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user",   "content": user_msg},
            ],
            temperature=0.1,
            max_tokens=2000,
            response_format={"type": "json_object"},
        )
        raw = resp.choices[0].message.content
        analysis = json.loads(raw)
        tokens = resp.usage.total_tokens
        logging.info(f"[LogMonitor] GPT-4o raspuns primit. Tokens folositi: {tokens}")
        return analysis

    except json.JSONDecodeError as ex:
        logging.error(f"[LogMonitor] Raspunsul GPT-4o nu este JSON valid: {ex}")
        return _fallback_analysis("Eroare parsare raspuns GPT-4o")
    except Exception as ex:
        logging.error(f"[LogMonitor] Eroare apel Azure OpenAI: {ex}", exc_info=True)
        return _fallback_analysis(str(ex))


def _fallback_analysis(error_msg: str) -> dict:
    return {
        "overall_status": "UNKNOWN",
        "summary": f"Analiza AI indisponibila: {error_msg}",
        "vm_status": {vm: "UNKNOWN" for vm in EXPECTED_VMS},
        "issues": [{"severity": "WARNING", "vm": "infrastructure",
                    "type": "SERVICE_ERROR",
                    "description": f"Analiza AI a esuat: {error_msg}",
                    "recommendation": "Verificati configuratia Azure OpenAI si Managed Identity."}],
        "security_summary": "Indisponibil",
        "recommendations": [],
    }


# ============================================================
# STEP 3: Emite rezultatele in Application Insights / Logs
# ============================================================

def _emit_results(analysis: dict, utc_now: datetime) -> None:
    """
    Logeaza analiza AI structurat.
    Toate mesajele ajung in Application Insights -> Traces
    si in Log Analytics -> AppTraces (tabelul workspace-ului).

    Interogare in portal:
      AppTraces
      | where Message startswith '[LogMonitor]'
      | order by TimeGenerated desc
    """
    status        = analysis.get("overall_status", "UNKNOWN")
    summary       = analysis.get("summary", "")
    issues        = analysis.get("issues", [])
    vm_status     = analysis.get("vm_status", {})
    sec_summary   = analysis.get("security_summary", "")
    recommendations = analysis.get("recommendations", [])

    critical_n = sum(1 for i in issues if i.get("severity") == "CRITICAL")
    warning_n  = sum(1 for i in issues if i.get("severity") == "WARNING")

    # Log principal — vizibil rapid in Logs
    status_line = (
        f"[LogMonitor] STATUS={status} | "
        f"CRITICAL={critical_n} WARNING={warning_n} | "
        f"{summary}"
    )
    if status == "CRITICAL" or critical_n > 0:
        logging.error(status_line)
    elif status == "WARNING" or warning_n > 0:
        logging.warning(status_line)
    else:
        logging.info(status_line)

    # VM status individual
    for vm, st in vm_status.items():
        msg = f"[LogMonitor][VM] {vm} = {st}"
        logging.warning(msg) if st == "OFFLINE" else logging.info(msg)

    # Fiecare problema individuala
    for issue in issues:
        sev  = issue.get("severity", "INFO")
        vm   = issue.get("vm", "?")
        typ  = issue.get("type", "")
        desc = issue.get("description", "")
        rec  = issue.get("recommendation", "")
        msg  = f"[LogMonitor][{sev}][{typ}] {vm}: {desc} => {rec}"
        if sev == "CRITICAL":
            logging.error(msg)
        elif sev == "WARNING":
            logging.warning(msg)
        else:
            logging.info(msg)

    # Securitate
    if sec_summary:
        logging.info(f"[LogMonitor][SECURITY] {sec_summary}")

    # Recomandari
    for i, rec in enumerate(recommendations, 1):
        logging.info(f"[LogMonitor][REC {i}] {rec}")

    # Dump complet JSON pentru interogari complexe
    logging.info(f"[LogMonitor][FULL_JSON] {json.dumps(analysis, ensure_ascii=False)}")
