# PLANUL COMPLET AL PROIECTULUI DE DISERTAȚIE

---

## 1. Titlul lucrării

**„Proiectarea, implementarea și securizarea unei infrastructuri cloud automatizate în Microsoft Azure utilizând Bicep, Packer și Ansible"**

**Subtitlu:** Studiu de caz privind adoptarea Infrastructure as Code și DevOps într-un mediu enterprise

### Argumentare academică

Titlul reflectă fidel:

- caracterul ingineresc și metodologic al lucrării („proiectarea, implementarea");
- accentul pe automatizare și securitate, două cerințe centrale în infrastructurile moderne;
- utilizarea explicită a tehnologiilor-cheie (Bicep, Packer, Ansible);
- contextul cloud și platforma aleasă (Microsoft Azure);
- existența unui studiu de caz, cerință frecventă pentru lucrările de nivel master.

Formularea este conformă cu stilul academic recomandat în lucrările tehnice de specialitate și evită ambiguitățile sau formulările prea comerciale.

---

## 2. Scenariul de studiu de caz

**SC MEDIA SRL** — companie de mici dimensiuni, specializată în furnizarea serviciilor de PR și Marketing. Compania dorește migrarea sistemelor informatice în cloud din motive de:

- securitate sporită;
- mobilitate și accesibilitate;
- reducerea costurilor de infrastructură fizică;
- continuitatea afacerii (disaster recovery).

Neavând personal IT calificat și nici expertiza necesară, SC MEDIA SRL apelează la **SC IT SECURITY SRL**, o companie specializată în securitate IT și infrastructuri cloud, pentru a proiecta, implementa și administra noul mediu.

---

## 3. Inventarul mediului (Environment Inventory)

### 3.1 Mașini virtuale (6 VM-uri)

| # | Nume VM | Sistem de operare | Rol | Subnet | Size Azure | Servicii principale |
|---|---------|-------------------|-----|--------|------------|---------------------|
| 1 | vm-jmp-01 | Ubuntu 22.04 LTS (imagine Packer jumphost) | Jumphost / Management | snet-mgmt (10.10.12.0/24) | Standard_B4ls_v2 | XFCE + xRDP (port 3389), Ansible Control Node, Azure CLI (MSI), Remmina |
| 2 | vm-web-01 | Ubuntu 22.04 LTS (imagine Packer base) | Server web (reverse proxy) | snet-prod (10.10.10.0/24) | Standard_B2s | nginx reverse proxy + SSL/TLS Let's Encrypt (port 443) |
| 3 | vm-app-01 | Ubuntu 22.04 LTS (imagine Packer base) | Server aplicații | snet-prod (10.10.10.0/24) | Standard_B2s | nginx backend API (port 8080) — 6 endpoint-uri JSON |
| 4 | vm-cms-01 | Ubuntu 22.04 LTS (imagine Packer base) | Server CMS / Mail | snet-prod (10.10.10.0/24) | Standard_B2s | WordPress + PHP-FPM + Postfix SMTP relay |
| 5 | vm-db-01  | Windows Server 2022 (imagine Packer) | Server bază de date | snet-prod (10.10.10.0/24) | Standard_B2s | MySQL Community Server 8.0 (port 3306) |
| 6 | vm-fs-01  | Windows Server 2022 (imagine Packer) | Server de fișiere | snet-prod (10.10.10.0/24) | Standard_B2s | SMB File Server — LanmanServer (share-uri departamentale) |

**IP-uri publice persistente (supraviețuiesc teardown):** pip-vm-jmp-01, pip-vm-web-01 (în `rg-mediasrl-persistent`).
**Toate celelalte IP-uri** sunt private, alocate dinamic de DHCP Azure.

### 3.2 Topologie rețea

**Arhitectură:** Flat VNet cu subnets multiple

| Resursă | CIDR | Scop |
|---------|------|------|
| **VNet** (vnet-mediasrl-productie) | 10.10.0.0/20 | Rețea virtuală principală (10.10.0.0 – 10.10.15.255, 4096 adrese) |
| **Subnet Production** (snet-prod) | 10.10.10.0/24 | VM-uri de producție (254 adrese utilizabile) |
| **Subnet Dev** (snet-dev) | 10.10.11.0/24 | Mediu de dezvoltare/testare (254 adrese utilizabile) |
| **Subnet Management** (snet-mgmt) | 10.10.12.0/24 | Jumphost și instrumente de administrare (254 adrese utilizabile) |

### 3.3 Diagrama logică a rețelei

```
                         ┌──────────────────────────────────────┐
                         │          INTERNET                     │
                         └──────────────┬───────────────────────┘
                                        │
                               [Public IPs — Persistent RG]
                              pip-vm-jmp-01  pip-vm-web-01
                              (RDP:3389/SSH)  (HTTPS:443)
                                   │              │
                         ┌─────────┴──────────────┴───────────────┐
                         │  vnet-mediasrl-productie (10.10.0.0/20)│
                         │                                        │
                         │  ┌──────────────────────────────────┐  │
                         │  │ snet-mgmt (10.10.12.0/24)        │  │
                         │  │   ┌───────────┐                  │  │
                         │  │   │ vm-jmp-01 │ (Jumphost)       │  │
                         │  │   │Ubuntu22.04│ XFCE+xRDP        │  │
                         │  │   │ B4ls_v2   │ Ansible+AzCLI    │  │
                         │  │   └─────┬─────┘                  │  │
                         │  │   SSH:22↓ WinRM:5985↓ RDP:3389↓  │  │
                         │  └─────────┼────────────────────────┘  │
                         │            │                           │
                         │  ┌─────────┴────────────────────────┐  │
                         │  │ snet-prod (10.10.10.0/24)        │  │
                         │  │                                  │  │
                         │  │  ┌───────────┐  ┌───────────┐    │  │
                         │  │  │vm-web-01  │  │vm-app-01  │    │  │
                         │  │  │Ubuntu22.04│  │Ubuntu22.04│    │  │
                         │  │  │nginx RP   │─→│nginx:8080 │    │  │
                         │  │  │SSL/HTTPS  │  │backend API│    │  │
                         │  │  └────┬──────┘  └───────────┘    │  │
                         │  │       │ proxy                    │  │
                         │  │       ▼                          │  │
                         │  │  ┌───────────┐  ┌──────────┐     │  │
                         │  │  │vm-cms-01  │  │vm-db-01  │     │  │
                         │  │  │Ubuntu22.04│  │Win 2022  │     │  │
                         │  │  │WordPress  │─→│MySQL 8.0 │     │  │
                         │  │  │+Postfix   │  │port 3306 │     │  │
                         │  │  └───────────┘  └──────────┘     │  │
                         │  │                ┌──────────┐      │  │
                         │  │                │vm-fs-01  │      │  │
                         │  │                │Win 2022  │      │  │
                         │  │                │SMB:445   │      │  │
                         │  │                └──────────┘      │  │
                         │  └──────────────────────────────────┘  │
                         │                                        │
                         │  ┌──────────────────────────────────┐  │
                         │  │ snet-dev (10.10.11.0/24)         │  │
                         │  │   (rezervat pentru mediu dev)    │  │
                         │  └──────────────────────────────────┘  │
                         │                                        │
                         └────────────────────────────────────────┘
```

### 3.4 Network Security Groups (NSG) — reguli de bază

**nsg-mgmt** (atașat la snet-mgmt):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop                         |
|------------|----------|-------|------|------|----------|---------|------------------------------|
| 100        | Inbound  | IP_admin | * | 3389 | TCP      | Allow   | RDP la jumphost (xRDP) din exterior |
| 110        | Inbound  | IP_admin | * | 22   | TCP      | Allow   | SSH la jumphost din exterior |
| 200        | Inbound  | *     | *    | *    | *        | Deny    | Blocare rest trafic extern   |

> IP_admin = IP-ul public al administratorului, detectat automat la deploy de `scripts/2-deploy-teardown-bicep.ps1`.

**nsg-prod** (atașat la snet-prod):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop |
|------------|----------|-------|------|------|----------|---------|------|
| 100 | Inbound | snet-mgmt | * | 3389 | TCP | Allow | RDP de la jumphost la Windows VMs |
| 110 | Inbound | snet-mgmt | * | 22 | TCP | Allow | SSH de la jumphost la Linux VMs |
| 115 | Inbound | snet-mgmt | * | 5985 | TCP | Allow | WinRM de la jumphost la Windows (Ansible) |
| 120 | Inbound | * | vm-web-01 | 443 | TCP | Allow | HTTPS la web server din exterior |
| 121 | Inbound | VirtualNetwork | vm-web-01 | 80 | TCP | Allow | HTTP doar din VNet (trafic intern reverse proxy) |
| 200 | Inbound | snet-prod | snet-prod | 3306 | TCP | Allow | MySQL intern (vm-cms-01 → vm-db-01) |
| 210 | Inbound | snet-prod | snet-prod | 25,587 | TCP | Allow | SMTP intern (Postfix) |
| 220 | Inbound | snet-prod | snet-prod | 445 | TCP | Allow | SMB intern (file server) |
| 300 | Inbound | * | * | * | * | Deny | Blocare rest trafic |

**nsg-dev** (atașat la snet-dev):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop |
|-----------|----------|-------|------|------|----------|---------|------|
| 100 | Inbound | snet-mgmt | * | 3389,22 | TCP | Allow | Acces de la jumphost |
| 200 | Inbound | * | * | * | * | Deny | Blocare rest trafic |

### 3.5 Componente suplimentare Azure

| Componentă | Resursă Azure | Scop | Cost estimat |
|-----------|--------------|------|-------------|
| **Gestionarea secretelor (infra)** | Azure Key Vault `kv-mediasrl-persistent` | Parole VM, MySQL, WordPress, ansible-vault-password | ~$0/lună (operații minime) |
| **Gestionarea secretelor (deployment)** | Azure Key Vault `kv-mediasrl-productie` | Secrete deployment Bicep | ~$0/lună |
| **Managed Identity (MSI)** | System-assigned MI pe vm-jmp-01 | Autentificare Azure fără credențiale hardcodate; acces KV secrets | $0 (gratuit) |
| **Monitorizare** | Azure Monitor + Log Analytics `log-mediasrl-productie` | Colectare loguri, metrici, alerte (Azure Monitor Agent pe toate VM-urile) | $0–$10/lună (free tier 5GB) |
| **Guvernanță** | Azure Policy | Impunerea conformității (tagging, locație, SKU-uri permise) | $0 (gratuit) |
| **IP-uri persistente** | Resource Group separat `rg-mediasrl-persistent` | IP-uri publice statice care supraviețuiesc ștergerii mediului | ~$8/lună (2 × Standard IP) |
| **WinRM Bootstrap automat** | `Microsoft.Compute/virtualMachines/runCommands` | Configurare WinRM pe Windows VMs la deployment (nu necesită intervenție manuală) | $0 (gratuit) |
| **Azure Compute Gallery** | `gal_mediasrl` în `rg-mediasrl-packer-swedencentral` | Stocarea imaginilor Packer (3 image definitions) | ~$0/lună (stocare mică) |
| **Backup** | Recovery Services Vault (dezactivat) | Backup VM-uri — dezactivat temporar (conflict la teardown); în investigare | — |

---

## 4. Estimare costuri Azure Monitor

### 4.1 Trafic generat de mediu

**Trafic de monitorizare (loguri → Log Analytics):**

| Sursă | Volum estimat/lună |
|-------|--------------------|
| Windows Event Logs (2 VM-uri × ~0.5–1 GB) | 1–2 GB |
| Linux Syslog (4 VM-uri × ~0.3–0.5 GB) | 1.2–2 GB |
| NSG Flow Logs (opțional) | 0.5–1 GB |
| **Total estimat** | **~2.7–5 GB/lună** |

**Free tier Log Analytics:** 5 GB/lună ingestie gratuită, 31 zile retenție.

**Concluzie:** Pentru acest mediu de 6 VM-uri, monitorizarea de bază se încadrează în **free tier** → **$0/lună**.

Dacă se activează VM Insights (opțional): +1–1.5 GB/VM/lună → total ~9–14 GB/lună → **~$10–$25/lună** (depășire free tier la $2.76/GB).

### 4.2 Trafic de rețea generat de aplicații

| Tip trafic | Estimare |
|-----------|----------|
| Website SC MEDIA SRL (site corporate, trafic scăzut: ~100–500 vizite/zi) | ~10–50 GB egress/lună |
| Email (SMTP, volum scăzut) | ~1–2 GB/lună |
| Administrare (RDP, SSH, updates) | ~5–10 GB/lună |
| **Total egress estimat** | **~15–60 GB/lună** |

**Azure network egress pricing:** Primii 100 GB/lună: ~$0.087/GB → **~$1–$5/lună**.

### 4.3 Cost total estimat mediu

| Resursă | Cost estimat/lună |
|---------|-------------------|
| 6 VM-uri (1× B4ls_v2 jumphost + 5× B2s producție) | ~$150 (~$50 + 5×$20) |
| Managed Disks (1×64GB + 2×128GB + 3×32GB Standard SSD) | ~$40 |
| Public IPs (2 × Standard SKU — jumphost + web) | ~$8 |
| Azure Monitor (free tier) | $0 |
| Key Vault | ~$0 |
| Network egress | ~$3 |
| Recovery Services Vault (dezactivat momentan) | — |
| **TOTAL ESTIMAT** | **~$200–$210/lună** |

> **Notă:** Costurile pot fi reduse semnificativ folosind Reserved Instances (1 an: ~40% reducere), spot VMs pentru Dev, sau oprirea VM-urilor în afara orelor de lucru.

---

## 5. Arhitectura conceptuală a soluției

### 5.1 Niveluri arhitecturale

```
┌─────────────────────────────────────────────────────────┐
│  Nivel 4: GUVERNANȚĂ, VERSIONARE ȘI AUTOMATIZARE       │
│  Azure DevOps (Repos + Pipelines)                       │
│  - Versionare cod (Git)                                 │
│  - CI/CD Pipelines (3 pipeline-uri YAML)               │
│  - Controlul modificărilor și audit                     │
│  - Loguri HTML de execuție per script                   │
├─────────────────────────────────────────────────────────┤
│  Nivel 3: CONFIGURARE ȘI ADMINISTRARE POST-PROVISIONING │
│  Ansible (de pe jumphost Ubuntu 22.04)                  │
│  - 13 roluri: baseline, nginx, mysql, wordpress,        │
│    postfix, fileserver, hardening, fail2ban,            │
│    ssh-hardening, modsecurity, monitoring, jumphost     │
│  - 6 playbook-uri numerotate + scripturi demo           │
│  - Ansible Vault (secrete preluate automat din KV)      │
│  - Azure Monitor Agent deployment                       │
├─────────────────────────────────────────────────────────┤
│  Nivel 2: CONSTRUIRE IMAGINI (GOLDEN IMAGES)            │
│  Packer                                                 │
│  - Ubuntu 22.04 LTS hardenizat (base + jumphost)        │
│  - Windows Server 2022 + WinRM pre-configurat           │
│  - Publicare în Azure Compute Gallery                   │
├─────────────────────────────────────────────────────────┤
│  Nivel 1: DEFINIRE INFRASTRUCTURĂ (IaC)                 │
│  Bicep (Azure-native)                                   │
│  - Resource Groups, VNet, Subnets, NSG                  │
│  - VM-uri (marketplace sau golden images Packer)        │
│  - Key Vault, Monitor Agent, Policy, RBAC               │
│  - IP-uri publice persistente (RG separat)              │
│  - WinRM bootstrap automat via runCommands              │
│  - Access policies KV pentru Managed Identity          │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Principii arhitecturale respectate

1. **Everything as Code** — toată infrastructura este definită declarativ
2. **Idempotență** — re-rularea aceluiași cod produce același rezultat
3. **Separarea responsabilităților** — fiecare unealtă are un rol clar definit
4. **Immutable Infrastructure** — imaginile Packer sunt construite, nu modificate
5. **Least Privilege** — accesul este restricționat prin NSG-uri, RBAC și KV policies
6. **Trasabilitate** — toate modificările sunt versionate în Git
7. **Secrets-free Code** — niciun secret nu este hardcodat; toate secretele sunt în Azure Key Vault

---

## 6. Planul de implementare (ordine logică și tehnică)

### Etapa 0 — Bootstrap Key Vault persistent ✅

- Script: `scripts/0-bootstrap-keyvault.ps1` (rulat O SINGURĂ DATĂ)
- Creează `rg-mediasrl-persistent` și `kv-mediasrl-persistent` via Bicep (`bicep/bootstrap/keyvault-persistent.bicep`)
- Solicită și stochează secretele de infrastructură:
  - `vm-admin-password`, `mysql-root-password`, `mysql-wordpress-password`
  - `mysql-monitoring-password`, `mysql-api-password`, `wordpress-admin-password`
  - `ansible-vault-password` (generat automat ca GUID random)
- Scriptul poate fi re-rulat pentru actualizarea parolelor

**Rezultat:** Key Vault persistent cu toate secretele, supraviețuiește oricărui teardown.

### Etapa 1 — Pregătirea mediului de dezvoltare ✅

- Instalarea Windows 11 (mașina de dezvoltare locală)
- Instalarea uneltelor:
  - Azure CLI, Packer (HashiCorp), Visual Studio Code + extensii (Bicep, Ansible, Azure)
- Configurarea autentificării Azure (`az login`)

**Rezultat:** Mediu local complet funcțional pentru IaC.

### Etapa 2 — Crearea imaginilor personalizate cu Packer ✅

- Definirea template-urilor Packer (format HCL) — 3 imagini:
  - **Ubuntu 22.04 LTS Base** (`imgdef-ubuntu2204`): update OS, pachete comune, SSH hardening, timezone, audit
  - **Ubuntu 22.04 LTS Jumphost** (`imgdef-ubuntu2204-jumphost`): XFCE, xRDP, Ansible + `azure.azcollection`, Azure CLI, VS Code, Firefox ESR, Remmina, `pywinrm`
  - **Windows Server 2022** (`imgdef-winserver2022`): WinRM pre-configurat, hardening de bază, Visual C++ Redistributable (necesar MySQL)
- Resource Group dedicat: `rg-mediasrl-packer-swedencentral`
- Azure Compute Gallery: `gal_mediasrl` cu 3 image definitions
- Script automatizat de build: `scripts/1-build-packer-images.ps1` (auto-increment versiune, confirmare interactivă, logging HTML)
- Imaginile sunt active în producție (`useMarketplaceImages = false` în `prod.bicepparam`)

**Rezultat:** Imagini standardizate, reutilizabile, securizate, publicate în Azure Compute Gallery.

### Etapa 3 — Definirea infrastructurii Azure cu Bicep ✅

- **Bootstrap KV persistent** (Etapa 0) — precondiție
- **14 module Bicep implementate:**
  - `resource-group.bicep` — Resource Group
  - `networking.bicep` — VNet, Subnets
  - `nsg.bicep` — Network Security Groups și reguli
  - `keyvault.bicep` — Azure Key Vault (deployment)
  - `monitoring.bicep` — Log Analytics Workspace + Action Group + Alert Rules
  - `policy.bicep` — Azure Policy Assignments (tagging, locație, SKU-uri)
  - `compute.bicep` — VM-uri cu NIC, OS Disk, **runCommands** pentru WinRM bootstrap
  - `persistent-ips.bicep` — IP-uri publice statice în RG separat
  - `ama.bicep` — Azure Monitor Agent pe toate VM-urile
  - `role-assignment.bicep` — RBAC role assignments (MSI jumphost)
  - `kv-access-policy.bicep` — Politici acces KV pentru Managed Identity jumphost
  - `vm-script-extension.bicep` — VM script extensions (fallback marketplace)
  - `backup.bicep` — Recovery Services Vault (**dezactivat** în main.bicep)
  - `backup-vm.bicep` — VM backup protection (**dezactivat** în main.bicep)
- **Script WinRM bootstrap automat:** `bicep/scripts/windows-winrm-bootstrap.ps1`
  - Rulat automat pe vm-db-01 și vm-fs-01 via `Microsoft.Compute/virtualMachines/runCommands` la deployment
  - Nu necesită intervenție manuală; log la `C:\Logs\mediasrl\winrm-bootstrap-*.log`
- **Parametrizare:** `bicep/parameters/prod.bicepparam` și `dev.bicepparam`
- **Deploy + Teardown:** `scripts/2-deploy-teardown-bicep.ps1`
  - Detectează automat IP-ul admin și îl adaugă la whitelist NSG
  - Rulează validate → what-if → confirmare → deploy
  - Generează log HTML de execuție în `logs/`

**Rezultat:** Infrastructură completă, declarativă, reproductibilă, idempotentă.

### Etapa 4 — Automatizarea configurării cu Ansible ✅

- Inventar dinamic Azure (`azure_rm.yml`) cu autentificare MSI (fără `az login`)
- **Ansible Vault automat:** `ansible/scripts/create-ansible-vault.sh`
  - Preia secretele din `kv-mediasrl-persistent` via Managed Identity
  - Creează `group_vars/all/vault.yml` encriptat AES-256
  - Parola vault stocată la `~/.vault-pass` (chmod 600)
- Script de deployment: `scripts/3-deploy-ansible-to-jumphost.ps1` (copiază ansible/ pe jumphost, declanșează create-ansible-vault.sh)
- **13 roluri Ansible implementate:**
  - `common` — baseline Linux: update, pachete, NTP, timezone, SSH hardening, firewalld
  - `nginx` — reverse proxy cu SSL/TLS Let's Encrypt pe vm-web-01 (HSTS, OCSP, security headers)
  - `appserver` — nginx backend API pe port 8080 (vm-app-01) — 6 endpoint-uri JSON
  - `wordpress` — WordPress + PHP 8.1 + PHP-FPM + WP-CLI pe vm-cms-01
  - `postfix` — server SMTP relay pe vm-cms-01
  - `mysql` — MySQL Community Server 8.0 pe vm-db-01 (Windows): instalare, baze de date, utilizatori, TDE, hardening
  - `fileserver` — SMB File Server pe vm-fs-01 (Windows): shares, NTFS ACL-uri, dezactivare SMBv1
  - `hardening` — CIS Benchmarks Linux + Windows: kernel hardening, audit, servicii, parole
  - `fail2ban` — protecție brute-force SSH pe Linux VMs
  - `ssh-hardening` — configurare avansată SSH (algoritmi, timeout, AllowUsers)
  - `modsecurity` — Web Application Firewall (ModSecurity) pe vm-web-01 (nginx)
  - `monitoring` — Azure Monitor Agent: colectare loguri Windows Event Log + Linux Syslog → Log Analytics
  - `jumphost` — configurare specifică jumphost Ubuntu (Ansible workspace, Remmina, MOTD)
- **6 playbook-uri principale (numerotate):**
  - `1-setup-ssh-keys.yml` — generare și distribuire chei SSH pe Linux VMs
  - `2-site.yml` — playbook principal de deployment complet (toate rolurile)
  - `3-verify.yml` — verificare servicii pe toate VM-urile (teste funcționale)
  - `4-harden-nginx-ssl.yml` — hardening SSL/TLS nginx (A+ SSL Labs grade)
  - `5-harden-security.yml` — hardening avansat: fail2ban, ssh-hardening, modsecurity, mysql hardening, TDE
  - `6-monitoring.yml` — instalare și configurare Azure Monitor Agent
- **Playbook suplimentar:**
  - `bootstrap-windows-winrm.yml` — activare WinRM manual (fallback dacă runCommands a eșuat)
- **Playbook-uri deprecate (în `playbooks/obsolete/`):**
  - `deploy-services.yml`, `harden-all.yml`, `test-services.yml`
- **Script wrapper:** `ansible/scripts/run-playbook.sh` — execuție playbook cu logging automat
  - Generează 3 fișiere per execuție: `.log` (ANSI color), `.clean.log` (text curat), `.html` (raport HTML detaliat)
  - Raportul HTML conține: metadate execuție, statistici per host, detalii per task, PLAY RECAP colorat
- **Demo-uri de securitate interactive (6 scripturi):**
  - `ansible/scripts/demo-1-rate-limiting.sh` — demonstrare rate limiting nginx (429 Too Many Requests)
  - `ansible/scripts/demo-2-fail2ban.sh` — demonstrare blocare IP cu fail2ban (brute-force SSH)
  - `ansible/scripts/demo-3-ssh-hardening.sh` — demonstrare respingere algoritmi slabi SSH
  - `ansible/scripts/demo-4-modsecurity.sh` — demonstrare blocări WAF ModSecurity (SQL injection, XSS, LFI, RCE)
  - `ansible/scripts/demo-5-mysql-hardening.sh` — demonstrare hardening MySQL: acces refuzat, TDE, audit log
  - `ansible/scripts/demo-all-hardenings.sh` — rulare secvențială a tuturor demo-urilor

**Rezultat:** Sisteme configurate uniform, securizate, monitorizate și administrabile automat.

### Etapa 5 — Integrarea completă în Azure DevOps ✅

- **3 pipeline-uri YAML implementate:**
  - **`pipelines/packer-build.yml`** — Build imagini Packer (manual, cu selecție per imagine)
    - 5 stage-uri: Setup Gallery → Build Ubuntu Base → Build Jumphost → Build Windows → Verify
    - Parametri runtime: `buildUbuntuBase`, `buildJumphost`, `buildWindows` (true/false)
    - Auto-increment versiune, timeout 60 min per imagine
  - **`pipelines/bicep-deploy.yml`** — Validate + What-If + Deploy infrastructură (automat pe push la `master`)
    - Stage 1 (Validate): `az bicep build` → `az deployment sub validate` → `az deployment sub what-if`
    - Stage 2 (Deploy): `az deployment sub create` cu aprobare manuală (Environment `production`)
    - Trigger automat pe modificări în `bicep/`
    - Rulează și pe Pull Requests (doar validare, fără deploy)
  - **`pipelines/ansible-configure.yml`** — Configurare VM-uri via Ansible pe jumphost (manual)
    - Copiază fișierele Ansible pe jumphost via SCP/rsync
    - Execută playbook-uri via SSH remote command
    - Parametri: alegere playbook, tags Ansible, nivel verbozitate
- **Template reutilizabil:** `pipelines/templates/az-login.yml`
- **Self-hosted agent** (Windows) — pool `Default`, scripturi PowerShell
- **Cerințe Azure DevOps:**
  - Service Connection `azure-service-connection` (Workload Identity Federation)
  - Variable Group `mediasrl-secrets`
  - Environment `production` cu approval gate

**Rezultat:** Flux DevOps complet automatizat (CI/CD), testat și funcțional.

### Etapa 6 — Testare, validare și demonstrații ✅

- **Suite de teste infrastructură:** `scripts/4-test-infrastructure.ps1`
  - 6 categorii: Azure Resources, Virtual Machines, Security, Connectivity, Idempotency, Performance
  - Verifică: Resource Groups, VNet, subnets, NSG-uri, Key Vault, Log Analytics, Gallery, 6 VM-uri Running
  - Teste securitate: reguli NSG, KV purge protection, Azure Policies, taguri obligatorii
  - Teste conectivitate: SSH/RDP la jumphost (TcpClient), HTTPS la webserver
  - Test idempotență: Bicep what-if verifică 0 modificări la re-deploy
  - Teste performanță: response time webserver, SSH connect time
  - Raport HTML + text generat în `logs/`
- **Suite de teste servicii Ansible:** `ansible/playbooks/obsolete/test-services.yml`
  - 10 secțiuni: Linux baseline, Windows baseline, Jumphost, Webserver, App server, CMS, File server, DB server, Cross-VM connectivity, Summary
  - Verifică: OS, timezone, SSH hardening, WinRM, MySQL, nginx, PHP-FPM, Postfix, SMB shares
- **Demo-uri de securitate (6 scripturi)** — demonstrații live ale măsurilor de securitate implementate
  - Rate limiting nginx, fail2ban, SSH hardening, ModSecurity WAF, MySQL hardening + TDE, demo complet combinat
  - Fiecare demo include atac simulat + dovada blocării + logging
- **Conținut demo generat** (coerent și interconectat):
  - **WordPress** (vm-cms-01): 5 pagini + 3 articole blog
  - **MySQL** (vm-db-01): baza `mediasrl_business` cu 5 tabele + date seed + views
  - **API REST** (vm-app-01): 6 endpoint-uri JSON
  - **File Server** (vm-fs-01): 6 documente demo departamentale
- **Logging execuție scripturi** (`scripts/lib/Write-Log.ps1`):
  - Toate scripturile PowerShell generează loguri `.log` (text) + `.html` (raport colorat, colapsibil) în `logs/`
  - Raportul HTML al execuției include: rezultate comenzilor az CLI, stare per resursă, timp de execuție

**Rezultat:** Infrastructura complet validată, cu demonstrații de securitate funcționale și conținut demo pentru prezentare.

---

## 7. Structura repository-ului (directoare)

```
IT/
├── packer/
│   ├── ubuntu-base/
│   │   ├── ubuntu-base.pkr.hcl         # Template Packer Ubuntu 22.04 Base
│   │   ├── variables.pkr.hcl           # Variabile (gallery RG, image def, etc.)
│   │   └── scripts/
│   │       └── base-setup.sh           # Update, pachete, SSH hardening, audit
│   ├── ubuntu-jumphost/
│   │   ├── ubuntu-jumphost.pkr.hcl     # Template Packer Ubuntu 22.04 Jumphost
│   │   ├── variables.pkr.hcl
│   │   └── scripts/
│   │       └── provision-jumphost.sh   # XFCE, xRDP, Ansible, Azure CLI, etc.
│   └── windows-server/
│       ├── windows-server.pkr.hcl      # Template Packer Windows Server 2022
│       ├── variables.pkr.hcl
│       └── scripts/
│           ├── base-setup.ps1          # Update, Visual C++, hardening de bază
│           ├── configure-winrm.ps1     # WinRM configurat pentru Ansible
│           └── hardening.ps1           # Hardening Windows (politici, servicii)
│
├── bicep/
│   ├── main.bicep                      # Orchestrator principal (subscription scope)
│   ├── bootstrap/
│   │   └── keyvault-persistent.bicep   # KV persistent (rulat o singură dată)
│   ├── modules/
│   │   ├── resource-group.bicep        # Resource Group
│   │   ├── networking.bicep            # VNet + Subnets
│   │   ├── nsg.bicep                   # Network Security Groups + reguli
│   │   ├── compute.bicep               # VM-uri + NIC + runCommands WinRM
│   │   ├── keyvault.bicep              # Key Vault (deployment)
│   │   ├── monitoring.bicep            # Log Analytics + Action Group + Alerts
│   │   ├── policy.bicep                # Azure Policy Assignments
│   │   ├── persistent-ips.bicep        # IP-uri publice statice
│   │   ├── ama.bicep                   # Azure Monitor Agent (toate VM-urile)
│   │   ├── role-assignment.bicep       # RBAC role assignments
│   │   ├── kv-access-policy.bicep      # Politici acces KV pentru MSI jumphost
│   │   ├── vm-script-extension.bicep   # VM script extensions (fallback marketplace)
│   │   ├── backup.bicep                # Recovery Services Vault (dezactivat)
│   │   └── backup-vm.bicep             # VM backup protection (dezactivat)
│   ├── scripts/
│   │   └── windows-winrm-bootstrap.ps1 # WinRM bootstrap (rulat automat via runCommands)
│   └── parameters/
│       ├── prod.bicepparam             # Parametri producție
│       └── dev.bicepparam              # Parametri dev
│
├── ansible/
│   ├── ansible.cfg                     # Configurație (vault_password_file = ~/.vault-pass)
│   ├── inventory/
│   │   ├── azure_rm.yml                # Inventar dinamic Azure (auth_source: msi) — PRIMAR
│   │   └── azure_rm_dev.yml            # Inventar dinamic — mediu dev
│   ├── group_vars/
│   │   ├── all/
│   │   │   └── vault.yml               # Secrete encriptate AES-256 (gitignored, creat automat)
│   │   ├── linux.yml                   # Variabile comune Linux VMs
│   │   ├── windows.yml                 # Variabile WinRM (parola din vault)
│   │   └── jumphost.yml                # Variabile specifice jumphost
│   ├── host_vars/
│   │   ├── vm-jmp-01/monitoring.yml    # Configurare monitoring per VM
│   │   ├── vm-web-01/monitoring.yml
│   │   ├── vm-app-01/monitoring.yml
│   │   ├── vm-cms-01/monitoring.yml
│   │   ├── vm-db-01/monitoring.yml
│   │   └── vm-fs-01/monitoring.yml
│   ├── playbooks/
│   │   ├── 1-setup-ssh-keys.yml        # Distribuire chei SSH pe Linux VMs
│   │   ├── 2-site.yml                  # Playbook principal — deploy complet
│   │   ├── 3-verify.yml                # Verificare servicii pe toate VM-urile
│   │   ├── 4-harden-nginx-ssl.yml      # Hardening SSL/TLS nginx (A+ grade)
│   │   ├── 5-harden-security.yml       # Hardening avansat (fail2ban, WAF, MySQL, TDE)
│   │   ├── 6-monitoring.yml            # Deploy Azure Monitor Agent
│   │   ├── bootstrap-windows-winrm.yml # Activare WinRM manual (fallback)
│   │   └── obsolete/                   # Playbook-uri depășite (nefolosite activ)
│   │       ├── deploy-services.yml
│   │       ├── harden-all.yml
│   │       └── test-services.yml
│   ├── roles/
│   │   ├── common/                     # Baseline Linux (pachete, NTP, SSH, firewall)
│   │   ├── nginx/                      # Reverse proxy + SSL/TLS + rate limiting
│   │   ├── appserver/                  # REST API pe nginx:8080
│   │   ├── wordpress/                  # WordPress + PHP-FPM + WP-CLI
│   │   ├── postfix/                    # SMTP relay
│   │   ├── mysql/                      # MySQL 8.0 pe Windows + TDE + hardening
│   │   ├── fileserver/                 # SMB File Server pe Windows
│   │   ├── hardening/                  # CIS Benchmarks Linux + Windows
│   │   ├── fail2ban/                   # Protecție brute-force SSH
│   │   ├── ssh-hardening/              # Hardening avansat SSH
│   │   ├── modsecurity/                # WAF ModSecurity pe nginx
│   │   ├── monitoring/                 # Azure Monitor Agent pe toate VM-urile
│   │   └── jumphost/                   # Configurare specifică jumphost
│   ├── scripts/
│   │   ├── create-ansible-vault.sh     # Preia secrete din KV via MSI + creeaza vault.yml
│   │   ├── run-playbook.sh             # Wrapper execuție playbook + logging .log/.clean.log/.html
│   │   ├── certbot-letsencrypt.sh      # Obținere/reînnoire certificat Let's Encrypt
│   │   ├── demo-1-rate-limiting.sh     # Demo: rate limiting nginx (429 Too Many Requests)
│   │   ├── demo-2-fail2ban.sh          # Demo: blocare IP brute-force SSH cu fail2ban
│   │   ├── demo-3-ssh-hardening.sh     # Demo: respingere algoritmi slabi SSH
│   │   ├── demo-4-modsecurity.sh       # Demo: blocări WAF (SQLi, XSS, LFI, RCE)
│   │   ├── demo-5-mysql-hardening.sh   # Demo: hardening MySQL + TDE + audit log
│   │   └── demo-all-hardenings.sh      # Rulare completă a tuturor demo-urilor
│   └── requirements.yml               # Ansible Galaxy collections (azure.azcollection etc.)
│
├── pipelines/
│   ├── packer-build.yml               # Pipeline: build imagini Packer (manual)
│   ├── bicep-deploy.yml               # Pipeline: validate + deploy Bicep (auto pe master)
│   ├── ansible-configure.yml          # Pipeline: configurare Ansible (manual)
│   └── templates/
│       └── az-login.yml               # Template reutilizabil: login Azure
│
├── scripts/
│   ├── 0-bootstrap-keyvault.ps1        # [O SINGURĂ DATĂ] Creare KV persistent + secrete
│   ├── 1-build-packer-images.ps1       # Build imagini Packer în Azure Compute Gallery
│   ├── 2-deploy-teardown-bicep.ps1     # Deploy sau teardown infrastructura Bicep
│   ├── 3-deploy-ansible-to-jumphost.ps1# Copiaza ansible/ pe jumphost + creeaza vault
│   ├── 4-test-infrastructure.ps1       # Suite de teste infrastructura Azure
│   ├── get-vm-ips.ps1                  # Afișare IP-uri VM-uri + generare inventory static
│   ├── lib/
│   │   └── Write-Log.ps1               # Librărie logging HTML + text (dot-sourced)
│   └── obsolete/
│       ├── bootstrap-jumphost.sh       # Bootstrap jumphost manual (înlocuit de imaginea Packer)
│       └── 2-deploy-bicep.ps1          # Versiune veche script deploy (înlocuit de 2-deploy-teardown)
│
├── logs/                               # Loguri de execuție generate automat (gitignored)
│   │                                   # Format per execuție: .log (ANSI), .clean.log (text), .html (raport)
│   └── (generat automat)
│
├── books/                              # Resurse documentare PDF
│
├── docs/
│   └── PLAN_PROIECT.md                 # Planul complet al proiectului
│
├── .gitignore
├── ARCHITECTURE_QUICK_REFERENCE.md     # Referință rapidă arhitectură
├── DEPLOYMENT_GUIDE.md                 # Ghid complet de deployment pas cu pas
├── INFRASTRUCTURE_UPDATE_SUMMARY.md    # Starea curentă a componentelor
└── README.md                           # Documentație principală proiect
```

---

## 8. Cuprinsul final al lucrării de disertație

### Capitolul 1 — Introducere
- 1.1 Contextul actual al industriei IT
- 1.2 Migrarea către cloud: tendințe și provocări
- 1.3 Necesitatea automatizării infrastructurii
- 1.4 Obiectivele lucrării
- 1.5 Metodologia de cercetare și structura lucrării

### Capitolul 2 — Fundamente teoretice
- 2.1 Cloud computing: modele, tipuri și furnizori
- 2.2 Infrastructure as Code (IaC): principii și beneficii
- 2.3 DevOps: cultură, practici și instrumente
- 2.4 Prezentarea tehnologiilor utilizate
  - 2.4.1 Microsoft Azure
  - 2.4.2 Bicep (limbaj IaC nativ Azure)
  - 2.4.3 Packer (construirea imaginilor personalizate)
  - 2.4.4 Ansible (automatizarea configurării)
  - 2.4.5 Azure DevOps (versionare și CI/CD)

### Capitolul 3 — Analiza cerințelor și scenariul de aplicabilitate
- 3.1 Prezentarea companiei SC MEDIA SRL
- 3.2 Prezentarea furnizorului SC IT SECURITY SRL
- 3.3 Cerințe funcționale
- 3.4 Cerințe non-funcționale (securitate, disponibilitate, scalabilitate)
- 3.5 Justificarea alegerii soluției și a tehnologiilor
- 3.6 Valoarea adăugată: de ce alege clientul externalizarea la SC IT SECURITY SRL
  - 3.6.1 Automatizare completă — infrastructura, de la zero la funcțional în ~30 minute
  - 3.6.2 Client fără personal IT — furnizorul preia tot (proiectare, implementare, securizare, mentenanță)
  - 3.6.3 Reutilizabilitatea codului — același stack (Bicep + Packer + Ansible) poate fi aplicat oricărui client nou
  - 3.6.4 Idempotență și disaster recovery — re-deploymentul complet durează minute, nu zile
  - 3.6.5 Securitate by design — NSG, CIS Benchmarks, KV, Vault, WAF, fail2ban implementate din start
  - 3.6.6 Transparență și auditabilitate — tot codul este versionat în Git; orice modificare este trasat
  - 3.6.7 Cost optimizat — free tier Azure Monitor, VM-uri burstable (B-series), IP-uri persistente
  - 3.6.8 Demonstrații live ale securității implementate — scripturi demo care dovedesc funcționalitatea
  - 3.6.9 Independența de furnizor — IaC în formate standard (Bicep, Packer HCL, Ansible YAML)

### Capitolul 4 — Arhitectura și proiectarea soluției
- 4.1 Arhitectura generală a soluției
- 4.2 Topologia de rețea
- 4.3 Rolul fiecărei tehnologii în arhitectură
- 4.4 Modelul de securitate și controlul accesului
- 4.5 Fluxuri de lucru (workflow-uri DevOps)
- 4.6 Convenții de denumire și organizare

### Capitolul 5 — Implementarea practică
- 5.1 Configurarea mediului de dezvoltare
- 5.2 Gestionarea secretelor cu Azure Key Vault
  - 5.2.1 Bootstrap Key Vault persistent (script 0-bootstrap-keyvault.ps1)
  - 5.2.2 Managed Identity — autentificare fără credențiale hardcodate
  - 5.2.3 Ansible Vault — creare automată din Key Vault via MSI
- 5.3 Crearea imaginilor personalizate cu Packer
  - 5.3.1 Imagine Ubuntu 22.04 LTS Base
  - 5.3.2 Imagine Ubuntu 22.04 LTS Jumphost (XFCE + Ansible)
  - 5.3.3 Imagine Windows Server 2022 (WinRM + hardening)
  - 5.3.4 Publicarea în Azure Compute Gallery
- 5.4 Definirea infrastructurii cu Bicep
  - 5.4.1 Modulul de rețea (VNet, Subnets, NSG)
  - 5.4.2 Modulul de calcul (VM-uri, WinRM bootstrap automat via runCommands)
  - 5.4.3 Modulul de monitorizare (Log Analytics, Azure Monitor Agent, Alerte)
  - 5.4.4 Modulul de guvernanță (Azure Policy, RBAC, KV access policies)
  - 5.4.5 IP-uri publice persistente (Resource Group separat)
  - 5.4.6 Orchestrarea și parametrizarea (main.bicep, prod.bicepparam)
  - 5.4.7 Scriptul de deployment și teardown (2-deploy-teardown-bicep.ps1)
  - 5.4.8 Loguri de execuție HTML (Write-Log.ps1)
- 5.5 Automatizarea configurării cu Ansible
  - 5.5.1 Configurări comune (baseline Linux)
  - 5.5.2 Configurarea serverului web (nginx reverse proxy + SSL/TLS)
  - 5.5.3 Configurarea serverului de aplicații (nginx backend API)
  - 5.5.4 Configurarea serverului de bază de date (MySQL 8.0 pe Windows)
  - 5.5.5 Configurarea serverului CMS/Mail (WordPress + Postfix)
  - 5.5.6 Configurarea serverului de fișiere (SMB pe Windows)
  - 5.5.7 Configurarea jumphost-ului (Ubuntu + Ansible Control Node)
  - 5.5.8 Monitorizarea (Azure Monitor Agent — rol Ansible)
  - 5.5.9 Script wrapper cu raportare HTML (run-playbook.sh)
- 5.6 Integrarea în Azure DevOps
  - 5.6.1 Structura repository-ului
  - 5.6.2 Pipeline-uri CI/CD
  - 5.6.3 Branch policies și code review

### Capitolul 6 — Securizarea infrastructurii
- 6.1 Modelul de securitate în depth (Defense in Depth)
- 6.2 Securizarea rețelei (NSG, segmentare, whitelist IP admin)
- 6.3 Hardenizarea imaginilor (CIS Benchmarks via Packer + Ansible)
- 6.4 Gestionarea secretelor (Azure Key Vault + Ansible Vault AES-256)
- 6.5 Controlul accesului (RBAC, Least Privilege, Managed Identity)
- 6.6 Guvernanța cu Azure Policy
- 6.7 SSL/TLS cu Let's Encrypt (certificat automat, HSTS, OCSP stapling)
- 6.8 Web Application Firewall (ModSecurity pe nginx)
- 6.9 Protecție brute-force (fail2ban + SSH hardening avansat)
- 6.10 Criptarea bazei de date (MySQL TDE — Transparent Data Encryption)
- 6.11 Monitorizarea și alertele de securitate (Azure Monitor)
- 6.12 Audit și conformitate (auditd Linux, Windows Event Log)
- 6.13 Demonstrații practice ale securității (demo scripts)

### Capitolul 7 — Testare și validare
- 7.1 Metodologii de testare aplicate
- 7.2 Teste funcționale (infrastructură + servicii)
  - 7.2.1 Suite PowerShell (4-test-infrastructure.ps1)
  - 7.2.2 Suite Ansible (playbooks/obsolete/test-services.yml)
- 7.3 Teste de idempotență (Bicep what-if → 0 modificări)
- 7.4 Teste de securitate (NSG, KV, Policies, taguri)
- 7.5 Teste de performanță (response time, connect time)
- 7.6 Demonstrații de securitate live (cele 6 demo scripts)
- 7.7 Probleme identificate pe parcurs și soluții aplicate
  - 7.7.1 Limita lungime cmd.exe (CSE) → migrat la runCommands
  - 7.7.2 Recovery Services Vault blochează teardown-ul → dezactivat backup în Bicep
  - 7.7.3 StrictMode PowerShell → verificări PSObject.Properties sigure
  - 7.7.4 MSI fără acces KV → adăugat modul kv-access-policy.bicep

### Capitolul 8 — Concluzii și recomandări
- 8.1 Sinteza rezultatelor
- 8.2 Contribuțiile lucrării
- 8.3 Valoarea comercială și reutilizabilitatea soluției
- 8.4 Limitări ale studiului
- 8.5 Direcții de cercetare viitoare

### Bibliografie

### Anexe
- Anexa A: Cod sursă Bicep (module complete)
- Anexa B: Template-uri Packer
- Anexa C: Playbook-uri Ansible
- Anexa D: Pipeline-uri Azure DevOps (YAML)
- Anexa E: Diagrame de arhitectură
- Anexa F: Rezultate teste și loguri HTML de execuție
- Anexa G: Demo-uri de securitate — output-uri capturate

---

## 9. Convenții de denumire (Naming Conventions)

### Resurse Azure

| Tip resursă | Pattern | Exemplu |
|------------|---------|---------|
| Resource Group | `rg-{proiect}-{mediu}-{regiune}` | `rg-mediasrl-productie-swedencentral` |
| Packer RG | `rg-{proiect}-packer-{regiune}` | `rg-mediasrl-packer-swedencentral` |
| Persistent RG | `rg-{proiect}-persistent` | `rg-mediasrl-persistent` |
| Virtual Network | `vnet-{proiect}-{mediu}` | `vnet-mediasrl-productie` |
| Subnet | `snet-{rol}` | `snet-prod`, `snet-dev`, `snet-mgmt` |
| NSG | `nsg-{subnet}` | `nsg-prod`, `nsg-dev`, `nsg-mgmt` |
| VM | `vm-{rol}-{nr}` | `vm-web-01`, `vm-db-01`, `vm-jmp-01` |
| NIC | `nic-{vm}` | `nic-vm-web-01` |
| OS Disk | `osdisk-{vm}` | `osdisk-vm-web-01` |
| Public IP | `pip-{vm}` | `pip-vm-jmp-01`, `pip-vm-web-01` |
| Key Vault | `kv-{proiect}-{mediu}` | `kv-mediasrl-productie`, `kv-mediasrl-persistent` |
| Log Analytics | `log-{proiect}-{mediu}` | `log-mediasrl-productie` |
| Compute Gallery | `gal_{proiect}` | `gal_mediasrl` |
| Image Definition | `imgdef-{os}` | `imgdef-ubuntu2204`, `imgdef-ubuntu2204-jumphost`, `imgdef-winserver2022` |

### Taguri obligatorii

| Tag | Valori | Scop |
|-----|--------|------|
| `environment` | `productie` / `dezvoltare` | Identificare mediu |
| `project` | `mediasrl` | Identificare proiect |
| `owner` | `IT Security SRL` | Responsabil |
| `managed-by` | `bicep` | Metodă de provisionare |

---

## 10. Fluxul DevOps complet (End-to-End)

```
[0] Bootstrap Key Vault (O SINGURĂ DATĂ)
        │   scripts/0-bootstrap-keyvault.ps1
        │   → kv-mediasrl-persistent cu toate secretele
        ▼
[1] Developer modifică cod (Bicep / Packer / Ansible)
        │
        ▼
[2] Git push → Azure DevOps Repos
        │
        ▼
[3] Pipeline CI se declanșează automat
        │
        ├──→ [Packer] Build golden images (dacă s-au modificat template-urile)
        │    scripts/1-build-packer-images.ps1
        │         │
        │         ▼
        │    Azure Compute Gallery (3 imagini actualizate)
        │
        ├──→ [Bicep] Validate → What-If → Deploy (cu aprobare manuală)
        │    scripts/2-deploy-teardown-bicep.ps1 -Action deploy
        │         │
        │         ▼
        │    Infrastructura Azure (VM-uri, rețea, securitate, KV, monitoring)
        │    + WinRM configurat automat pe Windows VMs via runCommands
        │    + Managed Identity jumphost cu acces KV secrets
        │    + Log HTML execuție în logs/
        │
        └──→ [Ansible] Configurare post-deploy (de pe jumphost)
             scripts/3-deploy-ansible-to-jumphost.ps1
                  │
                  ├── create-ansible-vault.sh (secrete din KV via MSI)
                  │
                  └── ansible-playbook playbooks/2-site.yml
                            │
                            ▼
                       VM-uri configurate: nginx, MySQL, WordPress,
                       Postfix, SMB, hardening, fail2ban, WAF,
                       SSH hardening, Azure Monitor Agent
                            │
                            ▼
                  [Testare & Validare]
                  scripts/4-test-infrastructure.ps1
                  ansible-playbook playbooks/3-verify.yml
                            │
                            ▼
                  [Securizare avansată]
                  ansible-playbook playbooks/4-harden-nginx-ssl.yml
                  ansible-playbook playbooks/5-harden-security.yml
                            │
                            ▼
                  [Monitoring]
                  ansible-playbook playbooks/6-monitoring.yml
                            │
                            ▼
                  [Demo-uri securitate]
                  ansible/scripts/demo-all-hardenings.sh
```

---

## 11. Reguli de lucru pe parcursul proiectului

1. **Documentația** — ton academic, cu diacritice, surse oficiale citate
2. **Comentarii cod** — fără diacritice, în limba engleză (best practice)
3. **Commit messages** — în limba engleză, descriptive
4. **Branch strategy** — `master` (protejat) + feature branches
5. **Fiecare capitol** va fi generat cu surse bibliografice oficiale
6. **Codul** va fi funcțional, testat și documentat

---

*Plan generat: 5 februarie 2026*
*Ultima actualizare: 12 iunie 2026*
