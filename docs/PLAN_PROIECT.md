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

| # | Nume VM | Sistem de operare | Rol | Subnet | Servicii principale |
|---|---------|-------------------|-----|--------|---------------------|
| 1 | vm-jmp-01 | Ubuntu 22.04 LTS | Jumphost / Management | Management (10.10.12.0/24) | XFCE + xRDP, Ansible Control Node, Azure CLI, Remmina, acces la toate VM-urile |
| 2 | vm-db-01 | Windows Server 2022 | Server bază de date | Production (10.10.10.0/24) | MySQL Community Server 8.0 |
| 3 | vm-fs-01 | Windows Server 2022 | Server de fișiere | Production (10.10.10.0/24) | SMB File Server (share-uri departamentale) |
| 4 | vm-web-01 | Ubuntu 22.04 LTS | Server web (reverse proxy) | Production (10.10.10.0/24) | nginx reverse proxy + SSL Let's Encrypt |
| 5 | vm-app-01 | Ubuntu 22.04 LTS | Server aplicații | Production (10.10.10.0/24) | nginx backend API (port 8080) |
| 6 | vm-cms-01 | Ubuntu 22.04 LTS | Server CMS / Mail | Production (10.10.10.0/24) | WordPress (CMS) + PHP-FPM + Postfix (mail) |

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
                               [Public IPs - Persistent RG]
                              pip-vm-jmp-01  pip-vm-web-01
                                   │              │
                         ┌─────────┴──────────────┴─────────────┐
                         │  vnet-mediasrl-productie (10.10.0.0/20)│
                         │                                       │
                         │  ┌─────────────────────────────────┐  │
                         │  │ snet-mgmt (10.10.12.0/24)       │  │
                         │  │   ┌───────────┐                 │  │
                         │  │   │ vm-jmp-01 │ (Jumphost)      │  │
                         │  │   │Ubuntu22.04│ XFCE+xRDP       │  │
                         │  │   │ Ansible   │ Control Node     │  │
                         │  │   └─────┬─────┘                 │  │
                         │  │         │ SSH/RDP to all VMs     │  │
                         │  └─────────┼───────────────────────┘  │
                         │            │                           │
                         │  ┌─────────┴───────────────────────┐  │
                         │  │ snet-prod (10.10.10.0/24)       │  │
                         │  │                                  │  │
                         │  │  ┌──────────┐  ┌──────────┐     │  │
                         │  │  │vm-web-01 │  │vm-app-01 │     │  │
                         │  │  │Ubuntu22.04│  │Ubuntu22.04│     │  │
                         │  │  │nginx RP  │─→│nginx:8080 │     │  │
                         │  │  │SSL/HTTPS │  │backend API│     │  │
                         │  │  └────┬─────┘  └──────────┘     │  │
                         │  │       │                          │  │
                         │  │       ▼                          │  │
                         │  │  ┌──────────┐  ┌──────────┐     │  │
                         │  │  │vm-cms-01 │  │vm-db-01  │     │  │
                         │  │  │Ubuntu22.04│  │Win 2022  │     │  │
                         │  │  │WordPress │  │MySQL 8.0 │     │  │
                         │  │  │+Postfix  │  └──────────┘     │  │
                         │  │  └──────────┘                    │  │
                         │  │                ┌──────────┐      │  │
                         │  │                │vm-fs-01  │      │  │
                         │  │                │Win 2022  │      │  │
                         │  │                │SMB Files │      │  │
                         │  │                └──────────┘      │  │
                         │  └──────────────────────────────────┘  │
                         │                                        │
                         │  ┌──────────────────────────────────┐  │
                         │  │ snet-dev (10.10.11.0/24)         │  │
                         │  │   (disponibil pt dezvoltare)     │  │
                         │  └──────────────────────────────────┘  │
                         │                                        │
                         └────────────────────────────────────────┘
```

### 3.4 Network Security Groups (NSG) — reguli de bază

**nsg-mgmt** (atașat la snet-mgmt):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop |
|-----------|----------|-------|------|------|----------|---------|------|
| 100 | Inbound | IP admin | * | 3389 | TCP | Allow | RDP la jumphost din exterior |
| 110 | Inbound | IP admin | * | 22 | TCP | Allow | SSH la jumphost din exterior |
| 200 | Inbound | * | * | * | * | Deny | Blocare rest trafic extern |

**nsg-prod** (atașat la snet-prod):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop |
|-----------|----------|-------|------|------|----------|---------|------|
| 100 | Inbound | snet-mgmt | * | 3389 | TCP | Allow | RDP de la jumphost la Windows |
| 110 | Inbound | snet-mgmt | * | 22 | TCP | Allow | SSH de la jumphost la Linux |
| 115 | Inbound | snet-mgmt | * | 5985 | TCP | Allow | WinRM de la jumphost la Windows (Ansible) |
| 120 | Inbound | * | vm-web-01 | 443 | TCP | Allow | HTTPS la web server |
| 121 | Inbound | * | vm-web-01 | 80 | TCP | Allow | HTTP la web server (ACME + redirect) |
| 200 | Inbound | snet-prod | snet-prod | 3306 | TCP | Allow | MySQL intern |
| 210 | Inbound | snet-prod | snet-prod | 25,587 | TCP | Allow | SMTP intern |
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
| **Gestionarea secretelor** | Azure Key Vault | Parole MySQL, chei SSH, certificate | ~$0/lună (operații minime) |
| **Monitorizare** | Azure Monitor + Log Analytics | Colectare loguri, metrici, alerte | $0–$10/lună (vezi detalii mai jos) |
| **Guvernanță** | Azure Policy | Impunerea conformității (tagging, locație, SKU-uri permise) | $0 (gratuit) |
| **Route Tables** | UDR (User Defined Routes) | Controlul rutării între subnets | $0 (gratuit) |
| **Backup** | Recovery Services Vault | Backup VM-uri critice | ~$5–$15/lună |
| **IP-uri persistente** | Resource Group separat (rg-mediasrl-persistent) | IP-uri publice statice care supraviețuiesc ștergerii mediului | ~$8/lună (2 × Standard IP) |
| **Bootstrap automat** | Custom Script Extension | Execuție automată scripturi la crearea VM-urilor | $0 (gratuit) |

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

**Recomandare:** Utilizăm Log Analytics cu free tier (suficient pentru acest mediu). Cost: **$0/lună**.

### 4.2 Trafic de rețea generat de aplicații

| Tip trafic | Estimare |
|-----------|----------|
| Website SC MEDIA SRL (site corporate, trafic scăzut: ~100–500 vizite/zi) | ~10–50 GB egress/lună |
| Email (SMTP, volum scăzut) | ~1–2 GB/lună |
| Administrare (RDP, SSH, updates) | ~5–10 GB/lună |
| **Total egress estimat** | **~15–60 GB/lună** |

**Azure network egress pricing:** Primii 100 GB/lună: ~$0.087/GB (în funcție de regiune) → **~$1–$5/lună**.

### 4.3 Cost total estimat mediu

| Resursă | Cost estimat/lună |
|---------|-------------------|
| 6 VM-uri (1× D2s_v3 jumphost + 5× B2s) | ~$190 (~$60 + 5×$26) |
| Managed Disks (1×64GB + 2×128GB + 3×32GB Standard SSD) | ~$40 |
| Public IPs (2 × Standard SKU — jumphost + web) | ~$8 |
| Azure Monitor (free tier) | $0 |
| Key Vault | ~$0 |
| Network egress | ~$3 |
| Recovery Services Vault (opțional) | ~$10 |
| **TOTAL ESTIMAT** | **~$250–$260/lună** |

> **Notă:** Costurile pot fi reduse semnificativ folosind Reserved Instances (1 an: ~40% reducere), spot VMs pentru Dev, sau oprirea VM-urilor în afara orelor de lucru.

---

## 5. Arhitectura conceptuală a soluției

### 5.1 Niveluri arhitecturale

```
┌─────────────────────────────────────────────────────────┐
│  Nivel 4: GUVERNANȚĂ, VERSIONARE ȘI AUTOMATIZARE       │
│  Azure DevOps (Repos + Pipelines)                       │
│  - Versionare cod (Git)                                 │
│  - CI/CD Pipelines                                      │
│  - Controlul modificărilor și audit                     │
├─────────────────────────────────────────────────────────┤
│  Nivel 3: CONFIGURARE ȘI ADMINISTRARE POST-PROVISIONING│
│  Ansible (de pe jumphost Ubuntu 22.04)                  │
│  - Configurări generale (update, firewall, securitate)  │
│  - Configurări specifice rolului (nginx, MySQL, CMS)    │
│  - Administrare continuă (patching, audit, hardening)   │
├─────────────────────────────────────────────────────────┤
│  Nivel 2: CONSTRUIRE IMAGINI (GOLDEN IMAGES)            │
│  Packer                                                 │
│  - Ubuntu 22.04 LTS hardenizat                          │
│  - Windows Server 2022 hardenizat                       │
│  - Publicare în Azure Compute Gallery                   │
├─────────────────────────────────────────────────────────┤
│  Nivel 1: DEFINIRE INFRASTRUCTURĂ (IaC)                 │
│  Bicep (Azure-native)                                   │
│  - Resource Groups, VNet, Subnets, NSG, Route Tables    │
│  - VM-uri (marketplace sau golden images)               │
│  - Key Vault, Monitor, Policy, Custom Script Extension  │
│  - IP-uri publice persistente (RG separat)              │
└─────────────────────────────────────────────────────────┘
```

### 5.2 Principii arhitecturale respectate

1. **Everything as Code** — toată infrastructura este definită declarativ
2. **Idempotență** — re-rularea aceluiași cod produce același rezultat
3. **Separarea responsabilităților** — fiecare unealtă are un rol clar definit
4. **Immutable Infrastructure** — imaginile Packer sunt construite, nu modificate
5. **Least Privilege** — accesul este restricționat prin NSG-uri și RBAC
6. **Trasabilitate** — toate modificările sunt versionate în Git

---

## 6. Planul de implementare (ordine logică și tehnică)

### Etapa 1 — Pregătirea mediului de dezvoltare ✅

- Instalarea Windows 11 (mașina de dezvoltare locală)
- Instalarea uneltelor:
  - Azure CLI
  - Packer (HashiCorp)
  - Visual Studio Code + extensii (Bicep, Ansible, Azure)
- Configurarea autentificării Azure:
  - Configurare Azure CLI (`az login`)
  - Configurare subscription și tenant ID

**Rezultat:** Mediu local complet funcțional pentru IaC.

### Etapa 2 — Crearea imaginilor personalizate cu Packer ✅

- Definirea template-urilor Packer (format HCL) — 3 imagini:
  - **Ubuntu 22.04 LTS Base** (`imgdef-ubuntu2204`): update OS, pachete comune, SSH hardening, timezone
  - **Ubuntu 22.04 LTS Jumphost** (`imgdef-ubuntu2204-jumphost`): XFCE, xRDP, Ansible, Azure CLI, VS Code, Firefox, Remmina
  - **Windows Server 2022** (`imgdef-winserver2022`): WinRM configurat pentru Ansible, firewall port 5985
- Resource Group dedicat: `rg-mediasrl-packer-swedencentral`
- Azure Compute Gallery: `gal_mediasrl` cu 3 image definitions
- Script automatizat de build: `scripts/build-packer-images.ps1` (auto-increment versiune, confirmare interactivă, logging)
- Imaginile sunt active în producție (`useMarketplaceImages = false` în `prod.bicepparam`)

**Rezultat:** Imagini standardizate, reutilizabile, securizate, publicate în Azure Compute Gallery.

### Etapa 3 — Definirea infrastructurii Azure cu Bicep ✅

- Crearea modulelor Bicep:
  - `resource-group.bicep` — Resource Group
  - `networking.bicep` — VNet, Subnets, Route Tables
  - `nsg.bicep` — Network Security Groups și reguli
  - `keyvault.bicep` — Azure Key Vault
  - `monitoring.bicep` — Log Analytics Workspace
  - `policy.bicep` — Azure Policy Assignments
  - `compute.bicep` — VM-uri cu NIC, OS Disk, Custom Script Extension
  - `persistent-ips.bicep` — IP-uri publice statice în RG separat
  - `backup.bicep` — Recovery Services Vault (dezactivat temporar)
- Parametrizare prin fișiere `.bicepparam` (prod.bicepparam)
- Custom Script Extension pentru bootstrap automat la crearea VM-urilor:
  - Linux (vm-jmp-01): `scripts/bootstrap-jumphost.sh`
  - Windows (vm-db-01, vm-fs-01): `scripts/bootstrap-windows-winrm.ps1`
- IP-uri publice persistente (supraviețuiesc `az group delete`)
- Deploy prin Azure CLI (`az deployment sub create`)

**Rezultat:** Infrastructură completă, declarativă, reproductibilă, idempotentă.

### Etapa 4 — Automatizarea configurării cu Ansible ✅

- Inventar dinamic Azure (`azure_rm.yml`) + inventar static de fallback (`hosts.ini`)
- **11 roluri Ansible implementate:**
  - `common` — baseline Linux (Ubuntu) și Windows (update, firewall, NTP, SSH hardening)
  - `nginx` — reverse proxy cu SSL Let's Encrypt pe vm-web-01
  - `appserver` — nginx backend API pe port 8080 pe vm-app-01
  - `wordpress` — WordPress + PHP-FPM pe vm-cms-01
  - `postfix` — server SMTP pe vm-cms-01
  - `mysql` — MySQL Community Server 8.0 pe vm-db-01 (Windows)
  - `fileserver` — SMB shares pe vm-fs-01 (Windows)
  - `hardening` — CIS Benchmarks (audit, kernel, servicii, parole)
  - `jumphost` — configurare Ubuntu jumphost (XFCE, xRDP, Ansible, az CLI)
  - `sqlserver` — SQL Server Express 2022 (alternativă la MySQL)
  - `mssql` — variantă alternativă SQL Server
- **5 playbook-uri:**
  - `site.yml` — orchestrator principal (7 faze: baseline → DB → app → files → hardening → verify)
  - `setup-ssh-keys.yml` — generare și distribuire chei SSH
  - `deploy-services.yml` — deploy doar servicii (fără baseline)
  - `harden-all.yml` — hardening CIS Benchmarks
  - `bootstrap-windows-winrm.yml` — activare WinRM via `az vm run-command`
- Conexiuni: SSH pentru Linux, WinRM (NTLM, port 5985) pentru Windows
- Ansible rulează de pe vm-jmp-01 (jumphost Ubuntu)

**Rezultat:** Sisteme configurate uniform și administrabile automat.

### Etapa 5 — Integrarea completă în Azure DevOps ✅

- **3 pipeline-uri YAML implementate:**
  - **`pipelines/packer-build.yml`** — Build imagini Packer (manual, cu selecție per imagine)
    - 5 stage-uri: Setup Gallery → Build Ubuntu Base → Build Jumphost → Build Windows → Verify
    - Parametri runtime: `buildUbuntuBase`, `buildJumphost`, `buildWindows` (true/false)
    - Auto-increment versiune, timeout 60 min per imagine
  - **`pipelines/bicep-deploy.yml`** — Validate + What-If + Deploy infrastructură (automat pe push la `master`)
    - Stage 1 (Validate): `az bicep build` → `az deployment sub validate` → `az deployment sub what-if`
    - Stage 2 (Deploy): `az deployment sub create` cu aprobare manuală (Environment `production`)
    - Trigger automat pe modificări în `bicep/` și `scripts/bootstrap-*`
    - Rulează și pe Pull Requests (doar validare, fără deploy)
  - **`pipelines/ansible-configure.yml`** — Configurare VM-uri via Ansible pe jumphost (manual)
    - Copiază fișierele Ansible pe jumphost via SCP/rsync
    - Execută playbook-uri via SSH remote command
    - Parametri: alegere playbook, tags Ansible, nivel verbozitate
- **Template reutilizabil:** `pipelines/templates/az-login.yml` (login Azure cu Service Connection)
- **Cerințe Azure DevOps:**
  - Service Connection `azure-service-connection` (Azure Resource Manager)
  - Variable Group `mediasrl-secrets` (adminPassword, sshPublicKey)
  - Environment `production` cu approval gate
  - Secure File `jumphost-ssh-key` (cheie SSH privată)

**Rezultat:** Flux DevOps complet automatizat (CI/CD).

### Etapa 6 — Testare, validare și optimizare ⏳

- Teste funcționale: verificare servicii (nginx, MySQL, WordPress, mail, SMB)
- Teste de securitate: NSG audit, port scanning, CIS compliance check
- Teste de idempotență: re-deploy Bicep + Ansible fără modificări
- Teste de performanță: response time website, throughput DB
- Identificare riscuri și remedieri
- Documentare rezultate

---

## 7. Structura repository-ului (directoare)

```
IT/
├── packer/
│   ├── ubuntu-base/
│   │   ├── ubuntu-base.pkr.hcl         # Template Packer Ubuntu 22.04 Base
│   │   ├── variables.pkr.hcl           # Variabile (gallery RG, image def, etc.)
│   │   └── scripts/
│   │       └── base-setup.sh           # Update, pachete comune, SSH hardening
│   ├── ubuntu-jumphost/
│   │   ├── ubuntu-jumphost.pkr.hcl     # Template Packer Ubuntu 22.04 Jumphost
│   │   ├── variables.pkr.hcl           # Variabile
│   │   └── scripts/
│   │       └── provision-jumphost.sh   # XFCE, xRDP, Ansible, Azure CLI, etc.
│   └── windows-server/
│       ├── windows-server.pkr.hcl      # Template Packer Windows Server 2022
│       ├── variables.pkr.hcl           # Variabile
│       └── scripts/
│           └── configure-winrm.ps1     # WinRM pentru Ansible
│
├── bicep/
│   ├── main.bicep                      # Orchestrator principal
│   ├── modules/
│   │   ├── resource-group.bicep        # Resource Group
│   │   ├── networking.bicep            # VNet, Subnets, Route Tables
│   │   ├── nsg.bicep                   # NSG + reguli
│   │   ├── compute.bicep               # VM-uri + Custom Script Extension
│   │   ├── keyvault.bicep              # Key Vault
│   │   ├── monitoring.bicep            # Log Analytics
│   │   ├── policy.bicep                # Azure Policy
│   │   ├── persistent-ips.bicep        # IP-uri publice persistente
│   │   └── backup.bicep                # Recovery Services Vault
│   └── parameters/
│       └── prod.bicepparam             # Parametri producție
│
├── ansible/
│   ├── ansible.cfg                     # Configurare Ansible
│   ├── inventory/
│   │   ├── azure_rm.yml                # Inventar dinamic Azure (principal)
│   │   └── hosts.ini                   # Inventar static (fallback)
│   ├── group_vars/
│   │   ├── linux.yml                   # Variabile grup Linux
│   │   ├── windows.yml                 # Variabile grup Windows
│   │   └── jumphost.yml                # Variabile jumphost
│   ├── playbooks/
│   │   ├── site.yml                    # Master playbook (7 faze)
│   │   ├── setup-ssh-keys.yml          # Distribuire chei SSH
│   │   ├── deploy-services.yml         # Deploy servicii
│   │   ├── harden-all.yml              # Hardening CIS
│   │   └── bootstrap-windows-winrm.yml # Bootstrap WinRM
│   ├── roles/
│   │   ├── common/                     # Baseline (Linux + Windows)
│   │   ├── nginx/                      # Reverse proxy + SSL
│   │   ├── appserver/                  # Backend API (nginx:8080)
│   │   ├── wordpress/                  # WordPress + PHP-FPM
│   │   ├── postfix/                    # Server mail SMTP
│   │   ├── mysql/                      # MySQL 8.0 (Windows)
│   │   ├── sqlserver/                  # SQL Server Express (alternativă)
│   │   ├── mssql/                      # SQL Server (variantă)
│   │   ├── fileserver/                 # SMB File Server (Windows)
│   │   ├── hardening/                  # CIS Benchmarks
│   │   └── jumphost/                   # Ubuntu jumphost management
│   └── files/
│       └── website/                    # Fișiere site SC MEDIA SRL
│
├── pipelines/
│   ├── packer-build.yml               # Pipeline: build imagini Packer (manual)
│   ├── bicep-deploy.yml               # Pipeline: validate + deploy Bicep (auto pe main)
│   ├── ansible-configure.yml          # Pipeline: configurare Ansible (manual)
│   └── templates/
│       └── az-login.yml               # Template reutilizabil: login Azure
│
├── scripts/
│   ├── bootstrap-jumphost.sh           # Bootstrap jumphost (CSE, fallback marketplace)
│   ├── bootstrap-windows-winrm.ps1     # Bootstrap WinRM (CSE, fallback marketplace)
│   └── build-packer-images.ps1         # Script automatizat build + publish imagini Packer
│
├── logs/                               # Output Packer builds (generat automat)
│
├── docs/
│   ├── PLAN_PROIECT.md                 # Planul complet al proiectului
│   └── disertatie/                     # Documentația lucrării
│       ├── capitole/
│       └── figuri/
│
├── .gitignore
├── DEPLOYMENT_GUIDE.md
└── README.md
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
  - 2.4.3 Packer (construirea imaginilor de mașini virtuale)
  - 2.4.4 Ansible (automatizarea configurării)
  - 2.4.5 Azure DevOps (versionare și CI/CD)

### Capitolul 3 — Analiza cerințelor și scenariul de aplicabilitate
- 3.1 Prezentarea companiei SC MEDIA SRL
- 3.2 Prezentarea furnizorului SC IT SECURITY SRL
- 3.3 Cerințe funcționale
- 3.4 Cerințe non-funcționale (securitate, disponibilitate, scalabilitate)
- 3.5 Justificarea alegerii soluției și a tehnologiilor

### Capitolul 4 — Arhitectura și proiectarea soluției
- 4.1 Arhitectura generală a soluției
- 4.2 Topologia de rețea
- 4.3 Rolul fiecărei tehnologii în arhitectură
- 4.4 Modelul de securitate și controlul accesului
- 4.5 Fluxuri de lucru (workflow-uri DevOps)
- 4.6 Convenții de denumire și organizare

### Capitolul 5 — Implementarea practică
- 5.1 Configurarea mediului de dezvoltare
- 5.2 Crearea imaginilor personalizate cu Packer
  - 5.2.1 Imagine Ubuntu 22.04 LTS
  - 5.2.2 Imagine Windows Server 2022
  - 5.2.3 Publicarea în Azure Compute Gallery
- 5.3 Definirea infrastructurii cu Bicep
  - 5.3.1 Modulul de rețea (VNet, Subnets, NSG)
  - 5.3.2 Modulul de calcul (VM-uri, Custom Script Extension)
  - 5.3.3 Modulul de monitorizare și guvernanță
  - 5.3.4 IP-uri publice persistente
  - 5.3.5 Orchestrarea și parametrizarea
- 5.4 Automatizarea configurării cu Ansible
  - 5.4.1 Configurări comune (baseline Linux și Windows)
  - 5.4.2 Configurarea serverului web (nginx reverse proxy + SSL)
  - 5.4.3 Configurarea serverului de aplicații (nginx backend)
  - 5.4.4 Configurarea serverului de bază de date (MySQL pe Windows)
  - 5.4.5 Configurarea serverului CMS/Mail (WordPress + Postfix)
  - 5.4.6 Configurarea serverului de fișiere (SMB pe Windows)
  - 5.4.7 Configurarea jumphost-ului (Ubuntu + Ansible Control Node)
  - 5.4.8 Hardening CIS Benchmarks
- 5.5 Integrarea în Azure DevOps
  - 5.5.1 Structura repository-ului
  - 5.5.2 Pipeline-uri CI/CD
  - 5.5.3 Branch policies și code review

### Capitolul 6 — Securizarea infrastructurii
- 6.1 Modelul de securitate în depth (Defense in Depth)
- 6.2 Securizarea rețelei (NSG, Route Tables, segmentare)
- 6.3 Hardenizarea imaginilor (CIS Benchmarks)
- 6.4 Gestionarea secretelor cu Azure Key Vault
- 6.5 Controlul accesului (RBAC, Least Privilege)
- 6.6 Guvernanța cu Azure Policy
- 6.7 SSL/TLS cu Let's Encrypt (certificat automat, HSTS, OCSP)
- 6.8 Monitorizarea și alertele de securitate
- 6.9 Audit și conformitate

### Capitolul 7 — Testare și validare
- 7.1 Metodologii de testare aplicate
- 7.2 Teste funcționale
- 7.3 Teste de idempotență
- 7.4 Teste de securitate
- 7.5 Teste de performanță
- 7.6 Probleme identificate și soluții aplicate

### Capitolul 8 — Concluzii și recomandări
- 8.1 Sinteza rezultatelor
- 8.2 Contribuțiile lucrării
- 8.3 Limitări ale studiului
- 8.4 Direcții de cercetare viitoare

### Bibliografie

### Anexe
- Anexa A: Cod sursă Bicep (module complete)
- Anexa B: Template-uri Packer
- Anexa C: Playbook-uri Ansible
- Anexa D: Pipeline-uri Azure DevOps (YAML)
- Anexa E: Diagrame de arhitectură
- Anexa F: Rezultate teste

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
| Route Table | `rt-{subnet}` | `rt-prod`, `rt-dev`, `rt-mgmt` |
| VM | `vm-{rol}-{nr}` | `vm-web-01`, `vm-db-01`, `vm-jmp-01` |
| NIC | `nic-{vm}` | `nic-vm-web-01` |
| OS Disk | `osdisk-{vm}` | `osdisk-vm-web-01` |
| Public IP | `pip-{vm}` | `pip-vm-jmp-01`, `pip-vm-web-01` |
| Key Vault | `kv-{proiect}-{mediu}` | `kv-mediasrl-productie` |
| Log Analytics | `log-{proiect}-{mediu}` | `log-mediasrl-productie` |
| Compute Gallery | `gal_{proiect}` | `gal_mediasrl` |
| Image Definition | `imgdef-{os}` | `imgdef-ubuntu2204`, `imgdef-winserver2022` |

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
[1] Developer modifică cod
        │
        ▼
[2] Git push → Azure DevOps Repos
        │
        ▼
[3] Pipeline CI se declanșează automat
        │
        ├──→ [Packer] Build golden images (dacă s-au modificat template-urile)
        │         │
        │         ▼
        │    Azure Compute Gallery (imagini noi)
        │
        ├──→ [Bicep] Validate → What-If → Deploy
        │         │
        │         ▼
        │    Infrastructura Azure (VM-uri, rețea, securitate)
        │    + Custom Script Extension (bootstrap automat)
        │
        └──→ [Ansible] Configurare post-deploy (de pe jumphost)
                  │
                  ▼
             VM-uri configurate și funcționale
```

---

## 11. Reguli de lucru pe parcursul proiectului

1. **Documentația** — ton academic, cu diacritice, surse oficiale citate
2. **Comentarii cod** — fără diacritice, în limba engleză (best practice)
3. **Commit messages** — în limba engleză, descriptive
4. **Branch strategy** — `main` (protejat) + feature branches
5. **Fiecare capitol** va fi generat cu surse bibliografice oficiale
6. **Codul** va fi funcțional, testat și documentat

---

*Plan generat: 5 februarie 2026*
*Ultima actualizare: 15 februarie 2026*
