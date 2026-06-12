# Deployment Guide — Infrastructura SC MEDIA SRL

**Ultima actualizare:** 2026-06-13

---

## Prezentare generala

Infrastructura SC MEDIA SRL se deployeaza in urmatoarele etape principale:

| Pas | Script / Unealta | Frecventa | Scop |
|-----|-----------------|-----------|------|
| **0** | `scripts/0-bootstrap-keyvault.ps1` | O singura data | Creaza KV persistent + populeaza secretele |
| **1** | `scripts/1-build-packer-images.ps1` | O data sau la actualizare imagini | Construieste imaginile golden Ubuntu + Windows |
| **2** | `scripts/2-deploy-teardown-bicep.ps1 -Action deploy` | La fiecare deploy | Deployeaza infrastructura Azure (VNet, NSG, VMs, KV, monitoring) |
| **3** | `scripts/3-deploy-ansible-to-jumphost.ps1` | Dupa fiecare deploy | Copiaza Ansible pe jumphost + creeaza Ansible Vault |
| **4** | Conectare RDP la jumphost | — | Acces la Ansible Control Node |
| **5** | `ansible-playbook playbooks/2-site.yml` | Dupa deploy infrastructura | Configureaza toate VM-urile (nginx, MySQL, WordPress etc.) |
| **6** | `ansible-playbook playbooks/4-harden-nginx-ssl.yml` | Post-configurare | Hardening SSL/TLS nginx (A+ SSL Labs) |
| **7** | `ansible-playbook playbooks/5-harden-security.yml` | Post-configurare | Hardening avansat: fail2ban, WAF, SSH, MySQL TDE |
| **8** | `ansible-playbook playbooks/6-monitoring.yml` | Post-configurare | Deploy Azure Monitor Agent pe toate VM-urile |
| **9** | `scripts/4-test-infrastructure.ps1` | La validare | Suite de teste infrastructura (Azure + conectivitate) |
| **10** | `scripts/demo-all-hardenings.sh` | Demo comisie | Demonstratii live de securitate cu raport HTML |

---

## Arhitectura VM-uri

| VM | OS | Rol | Subnet | IP |
|----|-----|-----|--------|----|
| vm-jmp-01 | Ubuntu 22.04 (imagine Packer jumphost) | Jumphost: XFCE + xRDP + Ansible Control Node | snet-mgmt | Public persistent |
| vm-web-01 | Ubuntu 22.04 (imagine Packer base) | nginx reverse proxy + SSL/TLS + ModSecurity WAF | snet-prod | Public persistent |
| vm-app-01 | Ubuntu 22.04 (imagine Packer base) | Application server — nginx backend API (port 8080) | snet-prod | Privat |
| vm-cms-01 | Ubuntu 22.04 (imagine Packer base) | WordPress + PHP-FPM + Postfix SMTP relay | snet-prod | Privat |
| vm-db-01  | Windows Server 2022 (imagine Packer) | MySQL Community Server 8.0 (port 3306) + TDE | snet-prod | Privat |
| vm-fs-01  | Windows Server 2022 (imagine Packer) | File Server SMB — share-uri departamentale | snet-prod | Privat |

---

## Cerinte preliminare

Pe masina locala (Windows):

- **Azure CLI** — `winget install Microsoft.AzureCLI`
- **Packer** — `winget install HashiCorp.Packer`
- **Bicep** — inclus in Azure CLI (`az bicep install`)
- **SSH client** — inclus in Windows 10/11 by default
- Autentificare: `az login`

---

## Pas 0: Bootstrap Key Vault (O SINGURA DATA)

Inainte de orice deployment, creeaza Key Vault-ul persistent si populeaza secretele de infrastructura.

```powershell
# Setup initial (prod)
.\scripts\0-bootstrap-keyvault.ps1

# Setup pentru dev
.\scripts\0-bootstrap-keyvault.ps1 -Environment dev
```

**Ce face:**
1. Creeaza `rg-mediasrl-persistent` (daca nu exista deja)
2. Deployeaza `kv-mediasrl-persistent` via `bicep/bootstrap/keyvault-persistent.bicep`
3. Solicita parolele de infrastructura — din fisier CSV sau interactiv
4. Stocheaza secretele in KV (rescrie fortat la fiecare rulare)
5. Genereaza automat `ansible-vault-password` (GUID random)
6. Genereaza log HTML in `logs/`

**Secrete stocate in `kv-mediasrl-persistent`:**

| Secret KV | Descriere |
|-----------|-----------|
| `vm-admin-password` | Parola admin pentru toate VM-urile (`azureadmin`) |
| `mysql-root-password` | Parola root MySQL |
| `mysql-wordpress-password` | Parola user MySQL pentru WordPress |
| `mysql-monitoring-password` | Parola user MySQL pentru monitoring |
| `mysql-api-password` | Parola user MySQL pentru API |
| `wordpress-admin-password` | Parola admin WordPress |
| `ansible-vault-password` | Parola vault Ansible (auto-generata — GUID) |

> **Nota:** Secretele supravietuiesc oricarui teardown al mediului principal. KV-ul persistent nu se sterge niciodata automat.

---

## Pas 1: Construire imagini Packer

Imaginile golden trebuie construite INAINTE de deployment-ul Bicep (necesar cu `useMarketplaceImages = false`).

```powershell
# Build interactiv (cu confirmare per imagine)
.\scripts\1-build-packer-images.ps1

# Build fara confirmare (CI/CD)
.\scripts\1-build-packer-images.ps1 -NoConfirm

# Skip recreere Gallery (daca exista deja)
.\scripts\1-build-packer-images.ps1 -SkipGallery
```

**Imagini create in `gal_mediasrl` (Azure Compute Gallery):**

| Image Definition | Continut |
|-----------------|----------|
| `imgdef-ubuntu2204` | Ubuntu 22.04 base: update, pachete comune, SSH hardening, timezone, auditd |
| `imgdef-ubuntu2204-jumphost` | Ubuntu 22.04 + XFCE Desktop + xRDP + Ansible + `azure.azcollection` + Azure CLI + VS Code + Remmina + `pywinrm` |
| `imgdef-winserver2022` | Windows Server 2022 + WinRM pre-configurat + Visual C++ Redistributable + hardening de baza |

**Resource Group Packer:** `rg-mediasrl-packer-swedencentral`
**Durata estimata:** 10–30 minute per imagine

---

## Pas 2: Deploy infrastructura Bicep

```powershell
# Deploy cu selectie interactiva
.\scripts\2-deploy-teardown-bicep.ps1

# Deploy direct (parametri)
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod

# Validare si what-if fara deploy
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod -ValidateOnly

# Deploy fara confirmare (CI/CD)
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod -NoConfirm
```

**Ce face scriptul:**
1. Detecteaza automat IP-ul public local si il adauga la whitelist NSG
2. Ruleaza `az deployment sub validate`
3. Afiseaza `az deployment sub what-if` (previzualizare modificari)
4. Cere confirmare inainte de creare (unless `-NoConfirm`)
5. Ruleaza `az deployment sub create`
6. Afiseaza IP-urile publice si pasii urmatori
7. Genereaza log HTML in `logs/`

**Durata estimata:** 8–15 minute

**Ce se creeaza:**

- 1 Resource Group principal: `rg-mediasrl-productie-swedencentral`
- 1 VNet (10.10.0.0/20) cu 3 subnets (snet-prod, snet-dev, snet-mgmt) + 3 NSG-uri
- 1 Key Vault deployment (`kv-mediasrl-productie`)
- 1 Log Analytics Workspace (`log-mediasrl-productie`)
- Azure Policies (subscription scope — tagging, locatie, SKU-uri)
- 6 VM-uri + NICs + OS Disks
- Azure Monitor Agent pe toate VM-urile (extensia `AzureMonitorLinuxAgent` / `AzureMonitorWindowsAgent`)
- RBAC role assignments (MSI jumphost: Reader pe RG persistent, Key Vault Secrets User pe KV persistent)
- KV access policies pentru Managed Identity jumphost
- WinRM configurat automat pe vm-db-01 si vm-fs-01 via `Microsoft.Compute/virtualMachines/runCommands`

> **Nota:** IP-urile publice persistente (pip-vm-jmp-01, pip-vm-web-01) si KV-ul persistent exista deja din Pas 0 si nu sunt recreate.

**Parametru imagini:**

| Valoare `useMarketplaceImages` | Comportament |
|-------------------------------|-------------|
| `false` (recomandat) | Foloseste imagini din `gal_mediasrl` (Packer golden images) |
| `true` (fallback) | Foloseste imagini marketplace standard (fara tool-uri pre-instalate) |

### Verificare post-deploy

```powershell
# Status VM-uri
az vm list -g rg-mediasrl-productie-swedencentral -o table `
  --query "[].{Name:name, State:powerState, OS:storageProfile.osDisk.osType}"

# IP-uri publice
az network public-ip list -g rg-mediasrl-persistent -o table `
  --query "[].{Name:name, IP:ipAddress}"

# Alternativ: scriptul dedicat
.\scripts\get-vm-ips.ps1
```

---

## Pas 3: Deploy Ansible pe jumphost

Copiaza directorul `ansible/` pe jumphost si ruleaza configurarea initiala:

```powershell
# Deploy cu prompt interactiv
.\scripts\3-deploy-ansible-to-jumphost.ps1

# Deploy cu parametri (CI/CD)
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod

# Deploy cu IP explicit
.\scripts\3-deploy-ansible-to-jumphost.ps1 `
  -JumphostIP 4.223.228.18 `
  -Environment prod
```

**Parametri disponibili:**

| Parametru | Default | Descriere |
|-----------|---------|-----------|
| `-JumphostIP` | `4.223.228.18` | IP public jumphost |
| `-User` | `azureadmin` | Username SSH |
| `-RemotePath` | `/home/azureadmin/ansible` | Cale destinatie pe jumphost |
| `-Environment` | prompt interactiv | `prod` sau `dev` |

**Ce face (3 pasi):**
1. **Copiere fisiere** — `scp ansible/* → jumphost:~/ansible/` (fallback: tar+SSH)
2. **Permisiuni + inventory** — seteaza chmod, activeaza `azure_rm.yml` pentru mediul ales, seteaza `website_domain` in `group_vars/linux.yml`
3. **Ansible Vault** — ruleaza `scripts/create-ansible-vault.sh` pe jumphost via SSH:
   - Autentificare Azure via Managed Identity (fara `az login`)
   - Preia secretele din `kv-mediasrl-persistent`
   - Creeaza `group_vars/all/vault.yml` encriptat AES-256
   - Salveaza parola vault la `~/.vault-pass` (chmod 600)

Genereaza log HTML in `logs/`.

---

## Pas 4: Conectare la Jumphost

### Obtine IP-ul public

```powershell
az network public-ip show `
  -g rg-mediasrl-persistent `
  -n pip-vm-jmp-01 `
  --query ipAddress -o tsv
```

### Conectare RDP (xRDP)

```powershell
mstsc /v:<IP_JUMPHOST>
```

Credentiale:
- **Username:** `azureadmin`
- **Password:** secretul `vm-admin-password` din `kv-mediasrl-persistent`

### Obtine parola din KV

```powershell
az keyvault secret show `
  --vault-name kv-mediasrl-persistent `
  --name vm-admin-password `
  --query value -o tsv
```

---

## Pas 5: Configurare VM-uri cu Ansible (din jumphost)

Dupa conectare RDP la vm-jmp-01 (Ubuntu + XFCE desktop), deschide un terminal:

### Verificare conectivitate

```bash
cd ~/ansible

# Linux VMs (SSH)
ansible all -m ping

# Windows VMs (WinRM)
ansible windows -m win_ping

# Afisare inventar dinamic
ansible-inventory -i inventory/azure_rm.yml --graph
```

### 5a. Distribuire chei SSH (primul deploy)

```bash
ansible-playbook playbooks/1-setup-ssh-keys.yml
```

Genereaza si distribuie chei SSH pe toate Linux VM-urile (necesara pentru conexiunile inter-VM).

### 5b. Deploy complet (toate rolurile)

```bash
ansible-playbook playbooks/2-site.yml
```

### 5c. Deploy selectiv cu tag-uri

```bash
# Baseline comun (NTP, pachete, firewall)
ansible-playbook playbooks/2-site.yml --tags common

# Jumphost post-configurare (shortcut-uri, MOTD)
ansible-playbook playbooks/2-site.yml --tags jumphost

# Webserver nginx (vm-web-01)
ansible-playbook playbooks/2-site.yml --tags webserver

# Application server API (vm-app-01)
ansible-playbook playbooks/2-site.yml --tags appserver

# CMS WordPress + Postfix (vm-cms-01)
ansible-playbook playbooks/2-site.yml --tags cms

# Database MySQL (vm-db-01, Windows)
ansible-playbook playbooks/2-site.yml --tags database

# File Server SMB (vm-fs-01, Windows)
ansible-playbook playbooks/2-site.yml --tags fileserver

# Hardening CIS Benchmarks Linux + Windows
ansible-playbook playbooks/2-site.yml --tags hardening

# Combinat (ex: webserver + CMS impreuna)
ansible-playbook playbooks/2-site.yml --tags nginx,wordpress
```

### 5d. Deploy pe VM-uri specifice

```bash
ansible-playbook playbooks/2-site.yml --limit webserver
ansible-playbook playbooks/2-site.yml --limit linux
ansible-playbook playbooks/2-site.yml --limit windows
ansible-playbook playbooks/2-site.yml --limit vm-cms-01
```

### 5e. Dry-run (check mode)

```bash
ansible-playbook playbooks/2-site.yml --check
```

### 5f. Wrapper cu logging automat (recomandat)

```bash
# Genereaza automat: .log (ANSI color), .clean.log (text), .html (raport HTML)
bash scripts/run-playbook.sh playbooks/2-site.yml

# Cu argumente extra
bash scripts/run-playbook.sh playbooks/2-site.yml --tags webserver
bash scripts/run-playbook.sh playbooks/2-site.yml --limit vm-web-01
```

Log-urile sunt salvate in `~/ansible/logs/` pe jumphost.

---

## Pas 6: Hardening avansat SSL/TLS

```bash
# Pe jumphost, din ~/ansible/
ansible-playbook playbooks/4-harden-nginx-ssl.yml
```

**Ce face:**
- Configureaza nginx pe vm-web-01 cu TLS 1.2/1.3 exclusiv
- ECDHE/DHE ciphers, dezactivare ciphers slabe
- HSTS cu `max-age=31536000` (1 an)
- OCSP stapling
- HTTP/2
- Tinteste grad **A+** pe SSL Labs

---

## Pas 7: Hardening avansat securitate

```bash
# Toate hardeningurile deodata
ansible-playbook playbooks/5-harden-security.yml

# Sau individual:
ansible-playbook playbooks/5-harden-security.yml --tags rate_limiting   # nginx rate limiting
ansible-playbook playbooks/5-harden-security.yml --tags fail2ban        # auto-ban IP brute-force
ansible-playbook playbooks/5-harden-security.yml --tags ssh_hardening   # algoritmi SSH moderni
ansible-playbook playbooks/5-harden-security.yml --tags modsecurity     # WAF OWASP CRS 3.2.1
ansible-playbook playbooks/5-harden-security.yml --tags mysql_hardening # MySQL hardening + TDE
```

**Ce configureaza:**

| Tag | VM | Configurare |
|-----|-----|-------------|
| `rate_limiting` | vm-web-01 | nginx: 5 req/min pe `/wp-login.php`, `/wp-admin/`, `/xmlrpc.php`, `/api/` |
| `fail2ban` | toate Linux | Auto-ban IP dupa 5 incercari esuate, ban 1 ora |
| `ssh_hardening` | toate Linux | curve25519 KEX, ChaCha20/AES-256-GCM, MACs ETM, AllowUsers azureadmin |
| `modsecurity` | vm-web-01 | ModSecurity On, OWASP CRS 3.2.1, paranoia level 1, excluderi WordPress |
| `mysql_hardening` | vm-db-01 | Stergere useri anonimi, test DB, `local_infile=OFF`, TDE InnoDB |

---

## Pas 8: Monitorizare (Azure Monitor Agent)

```bash
ansible-playbook playbooks/6-monitoring.yml
```

**Ce face:**
- Instaleaza si configureaza Azure Monitor Agent pe toate VM-urile (daca nu s-a instalat deja via Bicep)
- Configureaza colectare: Windows Event Log + Linux Syslog → Log Analytics `log-mediasrl-productie`
- Seteaza health check scripts (cron/Task Scheduler la 5 minute)
- Tag syslog: `mediasrl-health`

---

## Pas 9: Testare si validare

### Suite Azure (de pe masina locala)

```powershell
# Testare completa
.\scripts\4-test-infrastructure.ps1

# Skip testul de idempotenta (~5 minute)
.\scripts\4-test-infrastructure.ps1 -SkipIdempotency
```

**Categorii testate:**

| Categorie | Ce verifica |
|-----------|-------------|
| Azure Resources | Resource Groups, VNet, subnets, NSG-uri, Key Vault, Log Analytics, Gallery, Policies |
| Virtual Machines | 6 VM-uri existente si in stare Running |
| Security | Reguli NSG, KV purge protection, taguri obligatorii, Azure Policies |
| Connectivity | SSH la jumphost (:22), RDP la jumphost (:3389), HTTPS la webserver (:443) |
| Idempotency | Bicep what-if verifica 0 modificari la re-deploy |
| Performance | Response time webserver, SSH connect time |

Genereaza raport HTML + text in `logs/`.

### Suite Ansible (de pe jumphost)

```bash
# Verificare servicii pe toate VM-urile
ansible-playbook playbooks/3-verify.yml

# Suite completa de teste (playbook obsolete/test-services.yml)
ansible-playbook playbooks/obsolete/test-services.yml
```

---

## Pas 10: Demo-uri de securitate

De pe jumphost, din `~/ansible/`:

```bash
# Toate demo-urile secvential (recomandat pentru comisie)
bash scripts/demo-all-hardenings.sh

# Sau demo-uri individuale:
bash scripts/demo-1-rate-limiting.sh   # Rate limiting nginx (429 Too Many Requests)
bash scripts/demo-2-fail2ban.sh        # Ban IP brute-force SSH
bash scripts/demo-3-ssh-hardening.sh   # Respingere algoritmi slabi SSH
bash scripts/demo-4-modsecurity.sh     # Blocari WAF (SQLi, XSS, LFI, RCE)
bash scripts/demo-5-mysql-hardening.sh # MySQL hardening + TDE

# Rulare selectiva (ex. doar demo-urile 1 si 4)
bash scripts/demo-all-hardenings.sh --only 1,4

# Fara prompt-uri de confirmare (rulare automata)
bash scripts/demo-all-hardenings.sh --yes
```

**Output generat de fiecare demo:**

| Fisier | Continut |
|--------|----------|
| `logs/security-demos/demo-N-*-TIMESTAMP.html` | Raport HTML cu BEFORE/AFTER/DIFF, colorat, pentru comisie |
| `logs/security-demos/*-before.txt` | Starea initiala (vulnerabila) |
| `logs/security-demos/*-after.txt` | Starea dupa hardening (protejata) |
| `logs/security-demos/security-demo-report-*.html` | Raport master (toate hardeningurile) |

---

## Resurse create

```
Subscription (7a0255bf-...)
│
├── rg-mediasrl-persistent/              ← creat de Pas 0, supravietuieste teardown-ului
│   ├── pip-vm-jmp-01     (IP public static jumphost)
│   ├── pip-vm-web-01     (IP public static webserver, DNS label: mediasrl)
│   └── kv-mediasrl-persistent  (toate secretele de infrastructura)
│
├── rg-mediasrl-packer-swedencentral/    ← creat de Pas 1
│   └── gal_mediasrl
│       ├── imgdef-ubuntu2204
│       ├── imgdef-ubuntu2204-jumphost
│       └── imgdef-winserver2022
│
└── rg-mediasrl-productie-swedencentral/ ← creat de Pas 2 (STERS la teardown)
    ├── vnet-mediasrl-productie (10.10.0.0/20)
    │   ├── snet-prod (10.10.10.0/24)  + nsg-prod
    │   ├── snet-dev  (10.10.11.0/24)  + nsg-dev
    │   └── snet-mgmt (10.10.12.0/24)  + nsg-mgmt
    ├── kv-mediasrl-productie     (KV deployment)
    ├── log-mediasrl-productie    (Log Analytics Workspace)
    ├── vm-jmp-01, vm-web-01, vm-app-01, vm-cms-01, vm-db-01, vm-fs-01
    └── Azure Policies            (subscription scope)
```

---

## Teardown / Recreare environment

```powershell
# Sterge DOAR environment-ul principal (KV persistent + IP-urile supravietuiesc)
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod

# Re-deploy complet:
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod
# Dupa, reconecteaza RDP si ruleaza playbook-urile (Pasii 5-8)
```

**Nu se sterg niciodata:**
- `rg-mediasrl-persistent` (IP-uri statice + toate secretele KV)
- `rg-mediasrl-packer-swedencentral` (gallery + imagini Packer)

---

## Troubleshooting

### SSH: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"

Apare dupa re-deployment (VM nou = chei host noi):

```powershell
ssh-keygen -R <IP>
```

### Ansible: conectivitate SSH (Linux VMs)

```bash
ansible all -m ping -vvv
ssh azureadmin@<private-ip>
```

### Ansible: conectivitate WinRM (Windows VMs)

WinRM este configurat automat la deployment via `runCommands` Bicep.

```bash
# De pe jumphost
ansible windows -m win_ping -vvv

# Verificare pe VM (via RDP daca e necesar)
Test-WSMan -ComputerName localhost
winrm get winrm/config
Get-Service WinRM
```

Log bootstrap WinRM: `C:\Logs\mediasrl\winrm-bootstrap-*.log` pe Windows VMs.

### xRDP pe jumphost nu raspunde

```bash
# De pe jumphost via SSH
sudo systemctl status xrdp
sudo systemctl restart xrdp
firewall-cmd --list-all
```

### Ansible Vault: re-creare

```bash
cd ~/ansible
bash scripts/create-ansible-vault.sh
```

### Vizualizare IP-uri VM-uri

```powershell
# Script dedicat (afiseaza IP-uri + genereaza inventory static)
.\scripts\get-vm-ips.ps1

# Sau via az CLI
az vm list-ip-addresses -g rg-mediasrl-productie-swedencentral -o table
```

### Logs HTML de executie

Toate scripturile PowerShell si wrapper-ul Ansible genereaza loguri HTML in `logs/`:

```powershell
# Deschide ultimul log HTML generat
$latest = Get-ChildItem logs\*.html | Sort-Object LastWriteTime -Desc | Select-Object -First 1
Start-Process $latest.FullName
```

Rapoartele HTML contin: metadate executie, stare per resursa/task, PLAY RECAP colorat, butoane colapsibile.

---

## Azure DevOps — Pipeline-uri CI/CD

| Pipeline | Fisier | Trigger | Scop |
|----------|--------|---------|------|
| Packer Build | `pipelines/packer-build.yml` | Manual | Construieste imagini golden (3 imagini, selectabile) |
| Bicep Deploy | `pipelines/bicep-deploy.yml` | Auto (push pe `master`) | Validate + What-If + Deploy (cu aprobare manuala pe `production`) |
| Ansible Configure | `pipelines/ansible-configure.yml` | Manual | Ruleaza playbook-uri pe jumphost (selectie playbook + tags) |

**Cerinte Azure DevOps:**
- Service Connection: `azure-service-connection` (Workload Identity Federation)
- Variable Group: `mediasrl-secrets`
- Environment: `production` (cu approval gate pentru deploy)
- Agent pool: `Default` — self-hosted agent Windows

---

SC MEDIA SRL — Deployment Guide · furnizor: SC IT SECURITY SRL · 2026
