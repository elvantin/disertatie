# Infrastructura Cloud Automatizata — SC MEDIA SRL

**Proiect disertatie Master**: Proiectarea, implementarea si securizarea unei infrastructuri cloud automatizate in Microsoft Azure utilizand Bicep, Packer si Ansible

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
- **HTTP (80):** restrictionat la VNet — acces extern via HTTPS (443) prin nginx
- **WinRM (5985):** acces exclusiv din snet-mgmt (jumphost)

### Flux de trafic

```
Internet ──[HTTPS:443]──► vm-web-01 (nginx reverse proxy)
                              ├──[HTTP:80]──► vm-cms-01 (WordPress)
                              └──[HTTP:8080]──► vm-app-01 (REST API)

vm-cms-01 ──[MySQL:3306]──► vm-db-01 (MySQL 8.0)

Admin ──[RDP:3389]──► vm-jmp-01
vm-jmp-01 ──[SSH:22]──► vm-web-01, vm-app-01, vm-cms-01
vm-jmp-01 ──[WinRM:5985]──► vm-db-01, vm-fs-01
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
| Secrets | Azure Key Vault | Stocare securizata parole si secrete |
| Logging | HTML + text logs | Rapoarte colapsibile per executie script |

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
│   │   ├── compute.bicep               # VM + NIC + extensions
│   │   ├── keyvault.bicep              # Key Vault (main RG)
│   │   ├── monitoring.bicep            # Log Analytics + Action Group
│   │   ├── policy.bicep                # Azure Policies
│   │   ├── persistent-ips.bicep        # IP-uri publice statice
│   │   ├── ama.bicep                   # Azure Monitor Agent
│   │   ├── role-assignment.bicep       # RBAC role assignments
│   │   ├── kv-access-policy.bicep      # KV access policy (MSI jumphost)
│   │   ├── backup.bicep                # RSV vault (dezactivat)
│   │   └── backup-vm.bicep             # VM backup protection (dezactivat)
│   ├── scripts/
│   │   └── windows-winrm-bootstrap.ps1 # WinRM bootstrap (rulat automat via runCommands)
│   └── parameters/
│       ├── prod.bicepparam
│       └── dev.bicepparam
│
├── ansible/
│   ├── ansible.cfg                     # Configuratie Ansible
│   ├── inventory/
│   │   ├── azure_rm.yml                # Inventar dinamic Azure (auth_source: msi)
│   │   └── azure_rm_dev.yml            # Inventar dev
│   ├── group_vars/
│   │   ├── all/
│   │   │   └── vault.yml               # Secrete encriptate AES-256 (gitignored)
│   │   ├── linux.yml
│   │   ├── windows.yml
│   │   └── jumphost.yml
│   ├── playbooks/                      # Playbook-uri Ansible
│   ├── roles/
│   │   ├── common/                     # Baseline Linux
│   │   ├── nginx/                      # Reverse proxy + SSL
│   │   ├── appserver/                  # REST API
│   │   ├── wordpress/                  # WordPress + PHP-FPM
│   │   ├── postfix/                    # SMTP relay
│   │   ├── mysql/                      # MySQL 8.0 (Windows)
│   │   ├── fileserver/                 # SMB File Server (Windows)
│   │   └── hardening/                  # CIS Benchmarks
│   └── scripts/
│       ├── create-ansible-vault.sh     # Preia secrete din KV + creeaza vault.yml
│       └── demo-*.sh                   # Scripturi demo securitate
│
├── pipelines/
│   ├── packer-build.yml
│   ├── bicep-deploy.yml
│   └── ansible-configure.yml
│
├── scripts/
│   ├── 0-bootstrap-keyvault.ps1        # [O SINGURA DATA] Creeaza KV + secrete
│   ├── 1-build-packer-images.ps1       # Build imagini Packer
│   ├── 2-deploy-teardown-bicep.ps1     # Deploy / teardown infrastructura
│   ├── 3-deploy-ansible-to-jumphost.ps1# Copiaza ansible/ + ruleaza vault bootstrap
│   ├── 4-test-infrastructure.ps1       # Teste infrastructura Azure
│   ├── get-vm-ips.ps1                  # IP-uri VM-uri + genereaza hosts.ini
│   └── lib/
│       └── Write-Log.ps1               # Librarie logging HTML + text
│
├── logs/                               # Loguri HTML + text (generat automat)
├── docs/
│   └── PLAN_PROIECT.md
├── ARCHITECTURE_QUICK_REFERENCE.md
├── DEPLOYMENT_GUIDE.md
├── INFRASTRUCTURE_UPDATE_SUMMARY.md
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

### 2. Bootstrap Key Vault (o singura data)

```powershell
.\scripts\0-bootstrap-keyvault.ps1
```

### 3. Construire imagini Packer (o singura data)

```powershell
.\scripts\1-build-packer-images.ps1
```

### 4. Deploy infrastructura

```powershell
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
```

### 5. Deploy Ansible pe jumphost

```powershell
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod
```

### 6. Conectare la jumphost (RDP)

```powershell
# Obtine IP
az network public-ip show -g rg-mediasrl-persistent -n pip-vm-jmp-01 --query ipAddress -o tsv

# RDP
mstsc /v:<IP_JUMPHOST>
```

Username: `azureadmin` | Parola: din `kv-mediasrl-persistent` (secretul `vm-admin-password`)

### 7. Configurare cu Ansible (din jumphost)

```bash
cd ~/ansible
ansible all -m ping
ansible windows -m win_ping
ansible-playbook playbooks/2-site.yml
```

### 8. Testare

```powershell
.\scripts\4-test-infrastructure.ps1
```

---

## Securitate

- **NSG Rules** — segmentare retea, whitelist IP admin, deny-all implicit
- **CIS Benchmarks** — hardening Linux si Windows via Ansible
- **Key Vault** — stocare securizata secrete; ansible-vault-password generat automat
- **Ansible Vault** — `group_vars/all/vault.yml` AES-256, creat automat via MSI
- **Managed Identity** — jumphost autentificat via MSI (fara credentiale Azure hardcodate)
- **SSL/TLS** — Let's Encrypt + HSTS + OCSP stapling
- **WinRM** — configurat automat via Bicep runCommands; restrictionat la snet-mgmt
- **Audit Logging** — auditd (Linux) + Windows Event Log

---

## Teardown

```powershell
# Sterge environment-ul principal (IP-urile si KV persistent supravietuiesc)
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod

# Re-deploy:
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
```

---

## Documentatie

- [Deployment Guide](DEPLOYMENT_GUIDE.md) — ghid complet pas cu pas
- [Architecture Quick Reference](ARCHITECTURE_QUICK_REFERENCE.md) — referinta rapida arhitectura
- [Infrastructure Summary](INFRASTRUCTURE_UPDATE_SUMMARY.md) — stare curenta componente
- [Plan Proiect](docs/PLAN_PROIECT.md) — planul complet al proiectului de disertatie

---

## Autor

**SC IT SECURITY SRL** — Proiect disertatie Master — 2026
