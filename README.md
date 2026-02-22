# Infrastructura Cloud Automatizata - SC MEDIA SRL

**Proiect disertatie Master**: Proiectarea, implementarea si securizarea unei infrastructuri cloud automatizate in Microsoft Azure utilizand Bicep, Packer si Ansible

---

## Arhitectura

### Infrastructura (6 VM-uri)

| VM | OS | Rol | Subnet | IP Public | Specs |
|----|----|----|--------|-----------|-------|
| vm-jmp-01 | Ubuntu 22.04 LTS + XFCE + xRDP | Jumphost / Ansible Control Node | mgmt | Persistent | D2s_v3 (2 vCPU, 8GB RAM, 64GB SSD) |
| vm-web-01 | Ubuntu 22.04 LTS | Nginx reverse proxy + SSL/Let's Encrypt | prod | Persistent | B2s (2 vCPU, 4GB RAM, 32GB SSD) |
| vm-app-01 | Ubuntu 22.04 LTS | Application server (Nginx API port 8080) | prod | Privat | B2s (2 vCPU, 4GB RAM, 32GB SSD) |
| vm-cms-01 | Ubuntu 22.04 LTS | WordPress + PHP-FPM + Postfix | prod | Privat | B2s (2 vCPU, 4GB RAM, 32GB SSD) |
| vm-db-01 | Windows Server 2022 | MySQL Community Server 8.0 | prod | Privat | B2s (2 vCPU, 4GB RAM, 128GB SSD) |
| vm-fs-01 | Windows Server 2022 | File Server (SMB shares) | prod | Privat | B2s (2 vCPU, 4GB RAM, 128GB SSD) |

### Networking

- **VNet:** 10.10.0.0/20
- **Subnets:**
  - Management: 10.10.12.0/24
  - Production: 10.10.10.0/24
  - Development: 10.10.11.0/24
- **NSGs:** 3 Network Security Groups (mgmt, prod, dev)
- **Access:** RDP catre jumphost (port 3389), SSH intre VMs, WinRM catre Windows (port 5985)
- **HTTP (80):** Restrictionat doar la VNet (fara acces extern)
- **HTTPS (443):** Deschis public (SSL Let's Encrypt)

### Flux de trafic

```
Internet --> vm-web-01 (nginx reverse proxy, HTTPS:443)
               |-- proxy_pass --> vm-cms-01:80 (WordPress)
               |-- proxy_pass --> vm-app-01:8080 (API REST)

vm-cms-01 (WordPress) --> vm-db-01:3306 (MySQL - wordpress_db)
vm-app-01 (API) --> serveste JSON static (date coerente cu MySQL)

vm-jmp-01 (Ansible control node)
  |-- SSH --> vm-web-01, vm-app-01, vm-cms-01
  |-- WinRM --> vm-db-01, vm-fs-01
```

---

## Tehnologii utilizate

| Component | Tehnologie | Scop |
|-----------|------------|------|
| IaC | Azure Bicep | Definirea si deployment infrastructura |
| Golden Images | HashiCorp Packer | Template-uri hardened pentru Ubuntu si Windows |
| Config Management | Ansible | Configurare post-deployment si orchestrare |
| CI/CD | Azure DevOps Pipelines | Automatizare (3 pipeline-uri YAML) |
| Monitoring | Azure Monitor + Log Analytics | Observability (free tier 5GB/month) |
| Security | Azure Policy + CIS Benchmarks | Governance si hardening |
| Secrets | Azure Key Vault | Stocare securizata parole, chei SSH, certificate |

---

## Structura proiectului

```
IT/
├── packer/
│   ├── ubuntu-base/                    # Template Packer Ubuntu 22.04 Base
│   │   ├── ubuntu-base.pkr.hcl
│   │   ├── variables.pkr.hcl
│   │   └── scripts/base-setup.sh
│   ├── ubuntu-jumphost/                # Template Packer Ubuntu 22.04 Jumphost
│   │   ├── ubuntu-jumphost.pkr.hcl
│   │   ├── variables.pkr.hcl
│   │   └── scripts/provision-jumphost.sh
│   └── windows-server/                 # Template Packer Windows Server 2022
│       ├── windows-server.pkr.hcl
│       ├── variables.pkr.hcl
│       └── scripts/configure-winrm.ps1
│
├── bicep/
│   ├── main.bicep                      # Orchestrator principal
│   ├── modules/
│   │   ├── resource-group.bicep
│   │   ├── networking.bicep
│   │   ├── nsg.bicep
│   │   ├── compute.bicep
│   │   ├── keyvault.bicep
│   │   ├── monitoring.bicep
│   │   ├── policy.bicep
│   │   ├── persistent-ips.bicep
│   │   └── backup.bicep
│   └── parameters/
│       └── prod.bicepparam
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── azure_rm.yml                # Inventar dinamic Azure (principal)
│   │   └── hosts.ini                   # Inventar static (fallback)
│   ├── group_vars/
│   │   ├── linux.yml
│   │   ├── windows.yml
│   │   └── jumphost.yml
│   ├── playbooks/
│   │   ├── site.yml                    # Master playbook (7 faze)
│   │   ├── setup-ssh-keys.yml          # Distribuire chei SSH
│   │   ├── deploy-services.yml         # Deploy doar servicii
│   │   ├── harden-all.yml              # Hardening CIS Benchmarks
│   │   ├── harden-nginx-ssl.yml        # Hardening SSL/TLS nginx (A+ grade)
│   │   ├── bootstrap-windows-winrm.yml # Bootstrap WinRM
│   │   └── test-services.yml           # Teste servicii (Etapa 6)
│   └── roles/
│       ├── common/                     # Baseline (Linux + Windows)
│       ├── nginx/                      # Reverse proxy + SSL
│       ├── appserver/                  # Backend API (nginx:8080)
│       ├── wordpress/                  # WordPress + PHP-FPM + seed content
│       ├── postfix/                    # Server mail SMTP
│       ├── mysql/                      # MySQL 8.0 (Windows)
│       ├── sqlserver/                  # SQL Server Express (alternativa)
│       ├── mssql/                      # SQL Server (varianta)
│       ├── fileserver/                 # SMB File Server (Windows)
│       ├── hardening/                  # CIS Benchmarks
│       └── jumphost/                   # Ubuntu jumphost management
│
├── pipelines/
│   ├── packer-build.yml               # Pipeline: build imagini Packer (manual)
│   ├── bicep-deploy.yml               # Pipeline: validate + deploy Bicep (auto pe master)
│   ├── ansible-configure.yml          # Pipeline: configurare Ansible (manual)
│   └── templates/
│       └── az-login.yml               # Template reutilizabil: login Azure
│
├── scripts/
│   ├── bootstrap-jumphost.sh           # Bootstrap jumphost (CSE)
│   ├── bootstrap-windows-winrm.ps1     # Bootstrap WinRM (CSE)
│   ├── build-packer-images.ps1         # Script automatizat build imagini Packer
│   └── test-infrastructure.ps1         # Teste infrastructura Azure (Etapa 6)
│
├── logs/                               # Output Packer builds (generat automat)
├── docs/
│   └── PLAN_PROIECT.md                 # Planul complet al proiectului
├── .gitignore
├── DEPLOYMENT_GUIDE.md                 # Ghid detaliat de deployment
└── README.md
```

---

## Quick Start

### 1. Cerinte preliminare

```powershell
winget install Microsoft.AzureCLI
winget install HashiCorp.Packer
az bicep install
az login
```

### 2. Construire imagini Packer

```powershell
.\scripts\build-packer-images.ps1
```

### 3. Deploy infrastructura Bicep

```powershell
az deployment sub create --location swedencentral --template-file bicep/main.bicep --parameters bicep/parameters/prod.bicepparam
```

### 4. Conectare la jumphost

```powershell
# Obtine IP
az network public-ip show -g rg-mediasrl-persistent -n pip-vm-jmp-01 --query ipAddress -o tsv

# RDP
mstsc /v:<IP_JUMPHOST>
```

Credentiale: `azureadmin` / parola din `prod.bicepparam`

### 5. Configurare cu Ansible (din jumphost)

```bash
cd ~/ansible
ansible all -m ping
ansible windows -m win_ping
ansible-playbook playbooks/site.yml
```

### 6. Testare

```powershell
# Local (infrastructura Azure)
.\scripts\test-infrastructure.ps1

# Din jumphost (servicii VM-uri)
ansible-playbook playbooks/test-services.yml
```

Pentru detalii complete, vezi [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md).

---

## Securitate

- **Azure Policy** - Restrictii regiune, VM SKUs, taguri obligatorii
- **NSG Rules** - Segmentare retea, deny-all implicit, HTTP 80 doar intern
- **CIS Benchmarks** - Hardening Linux si Windows via Ansible
- **SSH Keys** - Chei SSH distribuite via Ansible dupa deployment initial
- **Key Vault** - Stocare securizata secrete
- **SSL/TLS** - Let's Encrypt cu HSTS, OCSP stapling
- **SSL Hardening** - Playbook dedicat: AES-256-GCM, DH 4096-bit, secp384r1 (A+ SSL Labs)
- **Firewalld** - Firewall pe jumphost
- **Audit Logging** - auditd (Linux) + Windows Event Log
- **AppArmor** - Ubuntu security framework

---

## Continut demo

Proiectul include continut demo coerent si interconectat pentru prezentarea de master:

| Sistem | Continut |
|--------|----------|
| WordPress (vm-cms-01) | 5 pagini (Acasa, Despre Noi, Servicii, Portofoliu, Contact) + 3 articole blog |
| MySQL (vm-db-01) | Baza de date `mediasrl_business`: 5 tabele (angajati, servicii, clienti, proiecte, facturi) + views |
| API REST (vm-app-01) | 6 endpoint-uri JSON: `/api/services`, `/api/clients`, `/api/projects`, `/api/team`, `/api/stats` |
| File Server (vm-fs-01) | 6 documente demo: regulament intern, calendar campanii, template propunere, proceduri backup |

Toate datele sunt coerente (aceiasi clienti, servicii, angajati in WordPress, MySQL si API).

---

## Azure DevOps Pipelines

| Pipeline | Fisier | Trigger | Scop |
|----------|--------|---------|------|
| Packer Build | `pipelines/packer-build.yml` | Manual | Construieste imagini golden in Azure Compute Gallery |
| Bicep Deploy | `pipelines/bicep-deploy.yml` | Auto (push pe `master`) | Valideaza si deployeaza infrastructura Azure |
| Ansible Configure | `pipelines/ansible-configure.yml` | Manual | Ruleaza playbook-uri Ansible pe jumphost |

Self-hosted agent Windows, pool `Default`.

---

## Jumphost (vm-jmp-01)

- **Desktop:** XFCE (lightweight, optimizat pentru RDP)
- **Remote Access:** xRDP (port 3389)
- **DevOps Tools:** Ansible, Azure CLI, VS Code, Git, htop, tmux, jq
- **Browser:** Firefox ESR
- **RDP Client:** Remmina cu profile pre-configurate pentru VM-urile Windows
- **Firewall:** firewalld (ports 22 SSH, 3389 RDP)
- **Workspace:** `~/ansible` pentru playbook-uri Ansible

---

## Documentatie

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Ghid complet de deployment pas cu pas
- [Plan Proiect](docs/PLAN_PROIECT.md) - Planul complet al proiectului de disertatie

---

## Autor

**SC IT SECURITY SRL** - Proiect disertatie Master
**Anul:** 2026

---

Acest proiect este destinat exclusiv pentru scopuri academice (disertatie master).
