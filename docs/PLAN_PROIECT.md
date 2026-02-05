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

### 3.1 Mașini virtuale (5 VM-uri)

| # | Nume VM | Sistem de operare | Rol | Subnet | Servicii principale |
|---|---------|-------------------|-----|--------|---------------------|
| 1 | vm-jmp-01 | Windows Server 2022 | Jumphost / Management | Management (10.10.12.0/24) | RDP, instrumente de administrare, acces la toate VM-urile |
| 2 | vm-db-01 | Windows Server 2022 | Server bază de date | Production (10.10.10.0/24) | MySQL Server |
| 3 | vm-web-01 | Rocky Linux 10 | Server web | Production (10.10.10.0/24) | nginx + site SC MEDIA SRL |
| 4 | vm-app-01 | Rocky Linux 10 | Server aplicații | Production (10.10.10.0/24) | Backend aplicație |
| 5 | vm-cms-01 | Rocky Linux 10 | Server CMS / Mail | Production (10.10.10.0/24) | WordPress (CMS) + Postfix (mail) |

### 3.2 Topologie rețea

**Arhitectură:** Flat VNet cu subnets multiple

| Resursă | CIDR | Scop |
|---------|------|------|
| **VNet** (vnet-media-prod) | 10.10.0.0/20 | Rețea virtuală principală (10.10.0.0 – 10.10.15.255, 4096 adrese) |
| **Subnet Production** (snet-prod) | 10.10.10.0/24 | VM-uri de producție (254 adrese utilizabile) |
| **Subnet Dev** (snet-dev) | 10.10.11.0/24 | Mediu de dezvoltare/testare (254 adrese utilizabile) |
| **Subnet Management** (snet-mgmt) | 10.10.12.0/24 | Jumphost și instrumente de administrare (254 adrese utilizabile) |

### 3.3 Diagrama logică a rețelei

```
                         ┌──────────────────────────────────────┐
                         │          INTERNET                     │
                         └──────────────┬───────────────────────┘
                                        │
                                   [Public IP]
                                        │
                         ┌──────────────┴───────────────────────┐
                         │     vnet-media-prod (10.10.0.0/20)   │
                         │                                       │
                         │  ┌─────────────────────────────────┐  │
                         │  │ snet-mgmt (10.10.12.0/24)       │  │
                         │  │   ┌───────────┐                 │  │
                         │  │   │ vm-jmp-01 │ (Jumphost)      │  │
                         │  │   │ Win 2022  │                 │  │
                         │  │   └─────┬─────┘                 │  │
                         │  │         │ RDP/SSH to all VMs     │  │
                         │  └─────────┼───────────────────────┘  │
                         │            │                           │
                         │  ┌─────────┴───────────────────────┐  │
                         │  │ snet-prod (10.10.10.0/24)       │  │
                         │  │                                  │  │
                         │  │  ┌──────────┐  ┌──────────┐     │  │
                         │  │  │vm-web-01 │  │vm-app-01 │     │  │
                         │  │  │Rocky  10 │  │Rocky  10 │     │  │
                         │  │  │nginx     │  │backend   │     │  │
                         │  │  └──────────┘  └──────────┘     │  │
                         │  │                                  │  │
                         │  │  ┌──────────┐  ┌──────────┐     │  │
                         │  │  │vm-cms-01 │  │vm-db-01  │     │  │
                         │  │  │Rocky  10 │  │Win 2022  │     │  │
                         │  │  │CMS+Mail  │  │MySQL     │     │  │
                         │  │  └──────────┘  └──────────┘     │  │
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
| 200 | Inbound | * | * | * | * | Deny | Blocare rest trafic extern |

**nsg-prod** (atașat la snet-prod):

| Prioritate | Direcție | Sursă | Dest | Port | Protocol | Acțiune | Scop |
|-----------|----------|-------|------|------|----------|---------|------|
| 100 | Inbound | snet-mgmt | * | 3389 | TCP | Allow | RDP de la jumphost la Windows |
| 110 | Inbound | snet-mgmt | * | 22 | TCP | Allow | SSH de la jumphost la Linux |
| 120 | Inbound | Internet | vm-web-01 | 80,443 | TCP | Allow | HTTP/HTTPS la web server |
| 200 | Inbound | snet-prod | snet-prod | 3306 | TCP | Allow | MySQL intern |
| 210 | Inbound | snet-prod | snet-prod | 25,587 | TCP | Allow | SMTP intern |
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

---

## 4. Estimare costuri Azure Monitor

### 4.1 Trafic generat de mediu

**Trafic de monitorizare (loguri → Log Analytics):**

| Sursă | Volum estimat/lună |
|-------|--------------------|
| Windows Event Logs (2 VM-uri × ~0.5–1 GB) | 1–2 GB |
| Linux Syslog (3 VM-uri × ~0.3–0.5 GB) | 0.9–1.5 GB |
| NSG Flow Logs (opțional) | 0.5–1 GB |
| **Total estimat** | **~2.5–4.5 GB/lună** |

**Free tier Log Analytics:** 5 GB/lună ingestie gratuită, 31 zile retenție.

**Concluzie:** Pentru acest mediu de 5 VM-uri, monitorizarea de bază se încadrează în **free tier** → **$0/lună**.

Dacă se activează VM Insights (opțional): +1–1.5 GB/VM/lună → total ~7–12 GB/lună → **~$5–$20/lună** (depășire free tier la $2.76/GB).

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
| 5 VM-uri (B2s: 2 vCPU, 4 GB RAM) | ~$150 ($30/VM) |
| Managed Disks (5 × 128 GB Standard SSD) | ~$50 |
| Public IP (1 × Standard SKU pt jumphost) | ~$4 |
| Azure Monitor (free tier) | $0 |
| Key Vault | ~$0 |
| Network egress | ~$3 |
| Recovery Services Vault (opțional) | ~$10 |
| **TOTAL ESTIMAT** | **~$210–$220/lună** |

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
│  Ansible                                                │
│  - Configurări generale (update, firewall, securitate)  │
│  - Configurări specifice rolului (nginx, MySQL, CMS)    │
│  - Administrare continuă (patching, audit)              │
├─────────────────────────────────────────────────────────┤
│  Nivel 2: CONSTRUIRE IMAGINI (GOLDEN IMAGES)            │
│  Packer                                                 │
│  - Rocky Linux 10 hardenizat                            │
│  - Windows Server 2022 hardenizat                       │
│  - Publicare în Azure Compute Gallery                   │
├─────────────────────────────────────────────────────────┤
│  Nivel 1: DEFINIRE INFRASTRUCTURĂ (IaC)                 │
│  Bicep (Azure-native)                                   │
│  - Resource Groups, VNet, Subnets, NSG, Route Tables    │
│  - VM-uri din golden images                             │
│  - Key Vault, Monitor, Policy                           │
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

### Etapa 1 — Pregătirea mediului de dezvoltare

- Instalarea Rocky Linux 10 (VM locală de dezvoltare)
- Instalarea uneltelor:
  - Azure CLI
  - Packer (HashiCorp)
  - Ansible
  - Visual Studio Code + extensii (Bicep, Ansible, Azure)
- Configurarea autentificării Azure:
  - Creare Service Principal
  - Configurare Azure CLI (`az login`)
  - Stocare credențiale în variabile de mediu

**Rezultat:** Mediu local complet funcțional pentru IaC.

### Etapa 2 — Crearea imaginilor personalizate cu Packer

- Definirea template-urilor Packer (format HCL):
  - **Rocky Linux 10:** update OS, hardening de bază, instalare pachete comune (curl, wget, vim, firewalld, etc.)
  - **Windows Server 2022:** update OS, hardening de bază, instalare features (IIS opțional, .NET, MySQL client tools)
- Aplicarea CIS Benchmarks de bază
- Publicarea imaginilor în **Azure Compute Gallery**

**Rezultat:** Imagini standardizate, reutilizabile, securizate.

### Etapa 3 — Definirea infrastructurii Azure cu Bicep

- Crearea modulelor Bicep:
  - `resource-group.bicep` — Resource Group
  - `networking.bicep` — VNet, Subnets, Route Tables
  - `nsg.bicep` — Network Security Groups și reguli
  - `keyvault.bicep` — Azure Key Vault
  - `monitoring.bicep` — Log Analytics Workspace, Diagnostic Settings
  - `policy.bicep` — Azure Policy Assignments
  - `compute.bicep` — VM-uri din imaginile Packer (NIC, OS Disk, etc.)
- Parametrizare pentru medii multiple (prod/dev) prin fișiere `.bicepparam`
- Validare (`az deployment sub what-if`) și deploy prin Azure CLI

**Rezultat:** Infrastructură completă, declarativă, reproductibilă, idempotentă.

### Etapa 4 — Automatizarea configurării cu Ansible

- Definirea inventarului dinamic (sau static) pentru cele 5 VM-uri
- **Playbook-uri generale:**
  - Update OS (Windows + Linux)
  - Configurare firewall (firewalld / Windows Firewall)
  - Politici de securitate (SSH hardening, disable root, password policies)
- **Playbook-uri specifice:**
  - **vm-web-01:** nginx + deploy site static SC MEDIA SRL
  - **vm-app-01:** configurare backend aplicație
  - **vm-cms-01:** WordPress + Postfix
  - **vm-db-01:** MySQL Server pe Windows
  - **vm-jmp-01:** instrumente administrare, configurare RDP
- Testarea idempotentei (rulări multiple, same result)

**Rezultat:** Sisteme configurate uniform și administrabile automat.

### Etapa 5 — Integrarea completă în Azure DevOps

- Creare organizație și proiect Azure DevOps
- Creare repository Git cu structura de directoare definită
- Configurare pipeline-uri YAML:
  - **Pipeline Packer:** build imagini → push la Gallery
  - **Pipeline Bicep:** validate → what-if → deploy
  - **Pipeline Ansible:** configurare post-deploy
- Configurare branch policies (code review, build validation)
- Configurare Service Connection pentru Azure

**Rezultat:** Flux DevOps complet automatizat (CI/CD).

### Etapa 6 — Testare, validare și optimizare

- Teste funcționale: verificare servicii (nginx, MySQL, WordPress, mail)
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
│   ├── rocky-linux/
│   │   ├── rocky-linux.pkr.hcl          # Template Packer Rocky Linux 10
│   │   ├── variables.pkr.hcl            # Variabile
│   │   └── scripts/
│   │       ├── base-setup.sh            # Update, pachete de bază
│   │       └── hardening.sh             # CIS hardening
│   └── windows-server/
│       ├── windows-server.pkr.hcl       # Template Packer Windows Server 2022
│       ├── variables.pkr.hcl            # Variabile
│       └── scripts/
│           ├── base-setup.ps1           # Update, features
│           └── hardening.ps1            # CIS hardening
│
├── bicep/
│   ├── main.bicep                       # Orchestrator principal
│   ├── modules/
│   │   ├── resource-group.bicep
│   │   ├── networking.bicep             # VNet, Subnets, Route Tables
│   │   ├── nsg.bicep                    # NSG + reguli
│   │   ├── compute.bicep                # VM-uri
│   │   ├── keyvault.bicep               # Key Vault
│   │   ├── monitoring.bicep             # Log Analytics, Diagnostic Settings
│   │   └── policy.bicep                 # Azure Policy
│   └── parameters/
│       ├── prod.bicepparam              # Parametri producție
│       └── dev.bicepparam               # Parametri dezvoltare
│
├── ansible/
│   ├── ansible.cfg                      # Configurare Ansible
│   ├── inventory/
│   │   ├── production.yml               # Inventar producție
│   │   └── development.yml              # Inventar dezvoltare
│   ├── playbooks/
│   │   ├── site.yml                     # Master playbook
│   │   ├── common.yml                   # Update OS, firewall, securitate
│   │   ├── webserver.yml                # nginx + site SC MEDIA SRL
│   │   ├── appserver.yml                # Backend aplicație
│   │   ├── cmsserver.yml                # WordPress + Postfix
│   │   ├── dbserver.yml                 # MySQL pe Windows
│   │   └── jumphost.yml                 # Configurare management
│   ├── roles/
│   │   ├── common/                      # Rol comun (update, securitate)
│   │   ├── nginx/                       # Rol nginx
│   │   ├── mysql/                       # Rol MySQL
│   │   ├── wordpress/                   # Rol WordPress
│   │   ├── postfix/                     # Rol Postfix
│   │   └── hardening/                   # Rol securitate
│   └── files/
│       └── website/                     # Fișiere site SC MEDIA SRL
│
├── pipelines/
│   ├── packer-build.yml                 # Pipeline build imagini
│   ├── bicep-deploy.yml                 # Pipeline deploy infrastructură
│   ├── ansible-configure.yml            # Pipeline configurare post-deploy
│   └── templates/
│       └── common-steps.yml             # Pași comuni reutilizabili
│
├── docs/
│   └── disertatie/                      # Documentația lucrării
│       ├── capitole/
│       └── figuri/
│
├── .gitignore
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
  - 5.2.1 Imagine Rocky Linux 10
  - 5.2.2 Imagine Windows Server 2022
  - 5.2.3 Publicarea în Azure Compute Gallery
- 5.3 Definirea infrastructurii cu Bicep
  - 5.3.1 Modulul de rețea (VNet, Subnets, NSG)
  - 5.3.2 Modulul de calcul (VM-uri)
  - 5.3.3 Modulul de monitorizare și guvernanță
  - 5.3.4 Orchestrarea și parametrizarea
- 5.4 Automatizarea configurării cu Ansible
  - 5.4.1 Configurări comune
  - 5.4.2 Configurarea serverului web (nginx)
  - 5.4.3 Configurarea serverului de bază de date (MySQL)
  - 5.4.4 Configurarea serverului CMS/Mail
  - 5.4.5 Configurarea jumphost-ului
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
- 6.7 Monitorizarea și alertele de securitate
- 6.8 Audit și conformitate

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
| Resource Group | `rg-{proiect}-{mediu}-{regiune}` | `rg-media-prod-westeurope` |
| Virtual Network | `vnet-{proiect}-{mediu}` | `vnet-media-prod` |
| Subnet | `snet-{rol}` | `snet-prod`, `snet-dev`, `snet-mgmt` |
| NSG | `nsg-{subnet}` | `nsg-prod`, `nsg-dev`, `nsg-mgmt` |
| Route Table | `rt-{subnet}` | `rt-prod`, `rt-dev`, `rt-mgmt` |
| VM | `vm-{rol}-{nr}` | `vm-web-01`, `vm-db-01`, `vm-jmp-01` |
| NIC | `nic-{vm}` | `nic-vm-web-01` |
| OS Disk | `osdisk-{vm}` | `osdisk-vm-web-01` |
| Public IP | `pip-{vm}` | `pip-vm-jmp-01` |
| Key Vault | `kv-{proiect}-{mediu}` | `kv-media-prod` |
| Log Analytics | `log-{proiect}-{mediu}` | `log-media-prod` |
| Compute Gallery | `gal_{proiect}` | `gal_media` |
| Image Definition | `imgdef-{os}` | `imgdef-rockylinux10`, `imgdef-winserver2022` |

### Taguri obligatorii

| Tag | Valori | Scop |
|-----|--------|------|
| `environment` | `prod` / `dev` | Identificare mediu |
| `project` | `media` | Identificare proiect |
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
        │
        └──→ [Ansible] Configurare post-deploy
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
*Ultima actualizare: 5 februarie 2026*
