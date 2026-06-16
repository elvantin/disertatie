# Infrastructura Cloud Automatizată — SC MEDIA SRL

**Proiect disertație Master**: Proiectarea, implementarea și securizarea unei infrastructuri cloud automatizate în Microsoft Azure utilizând Bicep, Packer și Ansible

---

## Arhitectura

### Infrastructura (6 VM-uri)

| VM | OS | Rol | Subnet | IP Public | Size |
|----|----|-----|--------|-----------|------|
| vm-jmp-01 | Ubuntu 22.04 LTS + XFCE + xRDP | Jumphost / Ansible Control Node | mgmt | Persistent | Standard_B4ls_v2 |
| vm-web-01 | Ubuntu 22.04 LTS | nginx reverse proxy + SSL/TLS | prod | Persistent | Standard_B2s |
| vm-app-01 | Ubuntu 22.04 LTS | Application server (port 8080) | prod | Privat | Standard_B2s |
| vm-cms-01 | Ubuntu 22.04 LTS | WordPress + PHP-FPM + Postfix | prod | Privat | Standard_B2s |
| vm-db-01  | Windows Server 2022 | MySQL Community Server 8.0 | prod | Privat | Standard_B2s |
| vm-fs-01  | Windows Server 2022 | File Server (SMB) | prod | Privat | Standard_B2s |

### Networking

- **VNet:** `vnet-mediasrl-productie` — 10.10.0.0/20
- **Subnets:** snet-mgmt 10.10.12.0/24 | snet-prod 10.10.10.0/24 | snet-dev 10.10.11.0/24
- **NSGs:** 3 Network Security Groups (mgmt, prod, dev)
- **HTTP (80):** restricționat la VNet — acces extern via HTTPS (443) prin nginx
- **WinRM (5985):** acces exclusiv din snet-mgmt (jumphost)

### Flux de trafic

```
Internet ──[HTTPS:443]──► vm-web-01 (nginx + ModSecurity WAF)
                              ├──[HTTP:80]──► vm-cms-01 (WordPress)
                              └──[HTTP:8080]──► vm-app-01 (REST API)

vm-cms-01 ──[MySQL:3306]──► vm-db-01 (MySQL 8.0 + TDE)

Admin ──[RDP:3389]──► vm-jmp-01 (xRDP)
vm-jmp-01 ──[SSH:22]──► vm-web-01, vm-app-01, vm-cms-01
vm-jmp-01 ──[WinRM:5985]──► vm-db-01, vm-fs-01
```

---

## Tehnologii utilizate

| Componentă | Tehnologie | Scop |
|------------|------------|------|
| IaC | Azure Bicep | Definirea și deployment infrastructura (14 module) |
| Golden Images | HashiCorp Packer | 3 imagini hardened: Ubuntu base, Ubuntu jumphost, Windows |
| Config Management | Ansible | 13 roluri, 7 playbooks, inventar dinamic MSI |
| CI/CD | Azure DevOps Pipelines | 4 pipeline-uri YAML (packer, bicep, ansible, function) |
| Monitoring | Azure Monitor + Log Analytics | AMA + DCR, free tier 5 GB/month |
| Secrets | Azure Key Vault | kv-mediasrl-persistent (bootstrap) + kv-mediasrl-productie (infra) |
| Vault | Ansible Vault AES-256 | group_vars/all/vault.yml generat automat via MSI |
| Logging | HTML + text logs | Write-Log.ps1 (PowerShell) + generate-demo-html.py (Ansible) |

---

## Structura proiectului

```
IT/
├── packer/
│   ├── ubuntu-base/                    # Template Packer Ubuntu 22.04 Base
│   ├── ubuntu-jumphost/                # Template Packer Ubuntu 22.04 Jumphost
│   └── windows-server/                 # Template Packer Windows Server 2022
│
├── bicep/
│   ├── main.bicep                      # Orchestrator principal (subscription scope)
│   ├── bootstrap/
│   │   └── keyvault-persistent.bicep   # KV persistent (run once)
│   ├── modules/
│   │   ├── resource-group.bicep
│   │   ├── networking.bicep            # VNet + subnets
│   │   ├── nsg.bicep                   # Network Security Groups
│   │   ├── compute.bicep               # VM + NIC + runCommands
│   │   ├── keyvault.bicep              # Key Vault (main RG)
│   │   ├── kv-access-policy.bicep      # KV access policy (MSI jumphost)
│   │   ├── monitoring.bicep            # Log Analytics + Action Group
│   │   ├── policy.bicep                # Azure Policies
│   │   ├── persistent-ips.bicep        # IP-uri publice statice
│   │   ├── ama.bicep                   # Azure Monitor Agent
│   │   ├── role-assignment.bicep       # RBAC role assignments
│   │   ├── backup.bicep                # RSV vault (dezactivat)
│   │   └── backup-vm.bicep             # VM backup protection (dezactivat)
│   ├── scripts/
│   │   └── windows-winrm-bootstrap.ps1 # WinRM bootstrap (rulat automat via runCommands)
│   └── parameters/
│       ├── prod.bicepparam
│       └── dev.bicepparam
│
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── azure_rm.yml                # Inventar dinamic Azure (auth_source: msi)
│   │   └── azure_rm_dev.yml
│   ├── group_vars/
│   │   ├── all/
│   │   │   └── vault.yml               # Secrete AES-256 (gitignored)
│   │   ├── linux.yml
│   │   ├── windows.yml
│   │   └── jumphost.yml
│   ├── playbooks/
│   │   ├── 1-setup-ssh-keys.yml        # Distribuire SSH keys
│   │   ├── 2-site.yml                  # Configurare completă toate VM-urile
│   │   ├── 3-verify.yml                # Verificare servicii + conectivitate
│   │   ├── 4-harden-nginx-ssl.yml      # Let's Encrypt + HSTS + OCSP
│   │   ├── 5-harden-security.yml       # fail2ban, SSH, ModSecurity, MySQL TDE
│   │   ├── 6-monitoring.yml            # Azure Monitor Agent + DCR
│   │   └── bootstrap-windows-winrm.yml # Bootstrap WinRM (fallback)
│   ├── roles/
│   │   ├── common/                     # Baseline Linux (NTP, auditd, updates)
│   │   ├── jumphost/                   # XFCE4, xRDP, Ansible, Azure CLI
│   │   ├── nginx/                      # Reverse proxy + rate limiting
│   │   ├── appserver/                  # REST API configurare
│   │   ├── wordpress/                  # WordPress + PHP-FPM + WP-CLI
│   │   ├── postfix/                    # SMTP relay + DKIM/SPF
│   │   ├── mysql/                      # MySQL 8.0 (Windows, WinRM)
│   │   ├── fileserver/                 # SMB shares (Windows)
│   │   ├── hardening/                  # CIS Benchmark L1
│   │   ├── fail2ban/                   # IP banning (SSH + nginx)
│   │   ├── ssh-hardening/              # Curve25519, ChaCha20, ECDH
│   │   ├── modsecurity/                # ModSecurity + OWASP CRS 3.2.1
│   │   └── monitoring/                 # Azure Monitor Agent + DCR
│   └── scripts/
│       ├── create-ansible-vault.sh     # Preia secrete din KV → vault.yml
│       ├── certbot-letsencrypt.sh      # Let's Encrypt wrapper
│       ├── demo-1-rate-limiting.sh     # Demo: nginx rate limiting
│       ├── demo-2-fail2ban.sh          # Demo: fail2ban IP ban
│       ├── demo-3-ssh-hardening.sh     # Demo: SSH algoritmi
│       ├── demo-4-modsecurity.sh       # Demo: WAF SQLi/XSS blocat
│       ├── demo-5-mysql-hardening.sh   # Demo: MySQL TDE + hardening
│       ├── demo-all-hardenings.sh      # Demo master (rulează toate 5)
│       └── lib/
│           └── generate-demo-html.py   # Generator rapoarte HTML demo
│
├── pipelines/
│   ├── packer-build.yml
│   ├── bicep-deploy.yml
│   ├── ansible-configure.yml
│   └── function-deploy.yml
│
├── scripts/
│   ├── 0-bootstrap-keyvault.ps1        # [O SINGURĂ DATĂ] Creare KV + secrete
│   ├── 1-build-packer-images.ps1       # Build imagini Packer
│   ├── 2-deploy-teardown-bicep.ps1     # Deploy / teardown infrastructura
│   ├── 3-deploy-ansible-to-jumphost.ps1# SCP ansible/ + vault bootstrap
│   ├── 4-test-infrastructure.ps1       # Teste infrastructura Azure
│   ├── get-vm-ips.ps1                  # IP-uri VM-uri + generează hosts.ini
│   └── lib/
│       └── Write-Log.ps1               # Logging HTML + text (colapsabil)
│
├── logs/                               # Loguri HTML + text (generat automat)
├── docs/
│   └── PLAN_PROIECT.md                 # Plan complet disertație (8 capitole)
├── ARCHITECTURE_QUICK_REFERENCE.md
├── DEPLOYMENT_GUIDE.md
├── infrastructure_update_summary.md
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

### 2. Bootstrap Key Vault (o singură dată)

```powershell
.\scripts\0-bootstrap-keyvault.ps1 -Environment prod
```

Creează `kv-mediasrl-persistent` în `rg-mediasrl-persistent` cu 7 secrete (parole VM, MySQL, domeniu, etc.).

### 3. Construire imagini Packer (o singură dată)

```powershell
.\scripts\1-build-packer-images.ps1
# sau cu parametri optionali:
.\scripts\1-build-packer-images.ps1 -SkipGallery -NoConfirm
```

### 4. Deploy infrastructură

```powershell
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
# sau doar validare:
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod -ValidateOnly
```

### 5. Deploy Ansible pe jumphost

```powershell
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod -JumphostIP <IP>
```

### 6. Conectare la jumphost (RDP)

```powershell
# Obtine IP
az network public-ip show -g rg-mediasrl-persistent -n pip-vm-jmp-01 --query ipAddress -o tsv

# RDP
mstsc /v:<IP_JUMPHOST>
```

Username: `azureadmin` | Parola: din `kv-mediasrl-persistent` → secretul `vm-admin-password`

### 7. Configurare completă cu Ansible (din jumphost)

```bash
cd ~/ansible

# Verificare inventar
ansible all -m ping
ansible windows -m win_ping

# Playbook-uri (în ordine)
ansible-playbook playbooks/1-setup-ssh-keys.yml
ansible-playbook playbooks/2-site.yml
ansible-playbook playbooks/3-verify.yml
ansible-playbook playbooks/4-harden-nginx-ssl.yml
ansible-playbook playbooks/5-harden-security.yml
ansible-playbook playbooks/6-monitoring.yml
```

### 8. Testare infrastructură

```powershell
.\scripts\4-test-infrastructure.ps1
# sau fara teste idempotenta (mai rapid):
.\scripts\4-test-infrastructure.ps1 -SkipIdempotency
```

---

## Securitate

### Stivă de securitate

| Componentă | Configurare |
|------------|-------------|
| **NSG Rules** | Segmentare rețea; whitelist IP admin; deny-all implicit |
| **CIS Benchmarks** | Hardening Linux L1: sysctl, PAM, SSH baseline |
| **nginx Rate Limiting** | 10 req/min pe `/wp-login.php`, `/api/`; burst 5 → 429 |
| **fail2ban** | SSH + nginx: 5 eșecuri → ban 1h via iptables |
| **SSH Hardening** | Curve25519, ChaCha20-Poly1305, ECDH-SHA2; algoritmi slabi eliminați |
| **ModSecurity WAF** | OWASP CRS 3.2.1 pe nginx — blochează SQLi, XSS, path traversal |
| **MySQL TDE** | InnoDB tablespace encryption (keyring_file); `local_infile=OFF` |
| **SSL/TLS** | Let's Encrypt; HSTS 31536000s; OCSP stapling; TLS 1.2/1.3 only |
| **Ansible Vault** | `group_vars/all/vault.yml` AES-256, creat automat via MSI |
| **Managed Identity** | vm-jmp-01 autentificat via MSI — fără credențiale Azure hardcodate |
| **Audit Logging** | auditd (Linux) + Windows Event Log + Log Analytics workspace |

### Demo-uri securitate (pentru comisie)

```bash
# Din ~/ansible/ pe jumphost:
./scripts/demo-all-hardenings.sh          # rulează toate 5 demo-uri
./scripts/demo-all-hardenings.sh --only 4 # doar ModSecurity WAF
./scripts/demo-all-hardenings.sh --yes    # fără pauze interactive
```

Fiecare demo generează un raport HTML în `logs/security-demos/` (dark theme, BEFORE/AFTER/DIFF colapsibil).

---

## Teardown

```powershell
# Sterge environment-ul principal (IP-urile și KV persistent supraviețuiesc)
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod

# Re-deploy complet:
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod -JumphostIP <IP>
```

---

## Documentație

- [Deployment Guide](DEPLOYMENT_GUIDE.md) — ghid complet pas cu pas (10 pași)
- [Architecture Quick Reference](ARCHITECTURE_QUICK_REFERENCE.md) — referință rapidă arhitectură
- [Infrastructure Summary](infrastructure_update_summary.md) — stare curentă componente
- [Plan Proiect](docs/PLAN_PROIECT.md) — planul complet al proiectului de disertație (8 capitole)

---

## Autor

**SC IT SECURITY SRL** — Proiect disertație Master — 2026
