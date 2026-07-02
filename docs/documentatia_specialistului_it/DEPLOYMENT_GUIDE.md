# Deployment Guide — Infrastructura SC MEDIA SRL

**Ultima actualizare:** 2026-06-16

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
| **5** | `ansible-playbook playbooks/1-setup-ssh-keys.yml` + `playbooks/2-site.yml` + `playbooks/3-verify.yml` | Dupa deploy infrastructura | Configureaza toate VM-urile (nginx, MySQL, WordPress etc.) |
| **6** | `scripts/certbot-letsencrypt.sh` | Post-configurare site | Obtine certificat Let's Encrypt pentru HTTPS |
| **7** | `ansible-playbook playbooks/4-harden-nginx-ssl_ssllabs.com_ssltest.yml` | Post-certificat | Hardening SSL/TLS nginx (A+ SSL Labs) |
| **8** | `scripts/demo-all-hardenings.sh` | Demo comisie | Demonstratii live de securitate cu raport HTML (deploy implicit playbook 5) |
| **9** | `ansible-playbook playbooks/6-monitoring.yml` | Post-securizare | Deploy health check scripts + cron/Task Scheduler |
| **10** | `scripts/4-test-infrastructure.ps1` | La validare | Suite de teste infrastructura (Azure + conectivitate) |
| **11** | intrebari comisie | — | — |

> **Nota executie demo-uri:** Demo-urile (Pas 8) deployeaza hardeningurile din playbook 5 in mod progresiv (BEFORE/AFTER). Daca nu se ruleaza demo-uri, se poate rula direct `playbooks/harden-security.yml` pentru a aplica toate hardeningurile deodata.

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
5. Genereaza automat `ansible-vault-password` (GUID aleator)
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
| `imgdef-ubuntu2204` | Ubuntu 22.04 base: update, pachete comune, SSH hardening, timezone Europe/Bucharest, auditd |
| `imgdef-ubuntu2204-jumphost` | Ubuntu 22.04 + XFCE Desktop + xRDP + Ansible + `azure.azcollection` + Azure CLI + VS Code + Remmina + `pywinrm` + timezone Europe/Bucharest |
| `imgdef-winserver2022` | Windows Server 2022 + WinRM pre-configurat + Visual C++ Redistributable + hardening de baza + timezone E. Europe Standard Time (Europe/Bucharest) |

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
- Finalizare jumphost via Custom Script Extension (`scripts/finalize-jumphost.sh`) la primul boot

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
3. **Ansible Vault** — ruleaza `ansible/scripts/create-ansible-vault.sh` pe jumphost via SSH:
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

### 5f. Verificare servicii dupa deploy

```bash
ansible-playbook playbooks/3-verify.yml
```

### 5g. Wrapper cu logging automat (recomandat)

```bash
# Genereaza automat: .log (ANSI color), .clean.log (text), .html (raport HTML)
# run-playbook.sh se afla in radacina ~/ansible/
bash run-playbook.sh playbooks/2-site.yml

# Cu argumente extra
bash run-playbook.sh playbooks/2-site.yml --tags webserver
bash run-playbook.sh playbooks/2-site.yml --limit vm-web-01
```

Log-urile sunt salvate in `~/ansible/logs/` pe jumphost.

---

## Pas 6: Certificat SSL Let's Encrypt

Obtine un certificat Let's Encrypt real pentru domeniul public al vm-web-01:

```bash
# Pe jumphost, din ~/ansible/
bash scripts/certbot-letsencrypt.sh

# Sau cu environment explicit
bash scripts/certbot-letsencrypt.sh --env prod
```

**Ce face:**
1. Deschide temporar portul 80 in NSG catre internet (pentru challenge HTTP-01)
2. Ruleaza certbot webroot challenge pe vm-web-01
3. Deployeaza configuratia nginx cu HTTPS activat
4. Inchide portul 80 inapoi la VNet-only (via trap, intotdeauna)

**Domeniu prod:** `mediasrl.swedencentral.cloudapp.azure.com`

> **Prerequisit:** MSI-ul jumphost trebuie sa aiba rolul `Network Contributor` pe NSG-ul corespunzator pentru a modifica regulile temporar.

---

## Pas 7: Hardening avansat SSL/TLS

```bash
# Pe jumphost, din ~/ansible/
ansible-playbook playbooks/4-harden-nginx-ssl_ssllabs.com_ssltest.yml
```

**Ce face:**
- Configureaza nginx pe vm-web-01 cu TLS 1.2/1.3 exclusiv
- DH Parameters 4096-bit (dureza 5–15 minute)
- ECDHE/DHE ciphers cu PFS, dezactivare ciphers slabe
- HSTS cu `max-age=31536000` (1 an) + `includeSubDomains`
- OCSP stapling
- Security headers: X-Frame-Options DENY, CSP, Permissions-Policy, Referrer-Policy
- Tinteste grad **A+** pe [SSL Labs](https://www.ssllabs.com/ssltest/)

**Verificare:** ruleaza testul SSL Labs inainte si dupa pentru comparatia de grad.

---

## Pas 8: Demo-uri de securitate

> **IMPORTANT:** Demo-urile deployeaza hardeningurile din playbook 5 progresiv (BEFORE → deploy → AFTER). Trebuie rulate INAINTE de a aplica manual playbook 5, altfel starea BEFORE este deja securizata si demo-ul nu mai are contrast.

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

### Alternativa fara demo-uri

Daca demo-urile nu se ruleaza (ex. environment deja partial securizat):

```bash
ansible-playbook playbooks/harden-security.yml

# Sau individual cu tag-uri:
ansible-playbook playbooks/harden-security.yml --tags rate_limiting
ansible-playbook playbooks/harden-security.yml --tags fail2ban
ansible-playbook playbooks/harden-security.yml --tags ssh_hardening
ansible-playbook playbooks/harden-security.yml --tags modsecurity
ansible-playbook playbooks/harden-security.yml --tags mysql_hardening
```

**Ce configureaza hardeningurile:**

| Tag | VM | Configurare |
|-----|-----|-------------|
| `rate_limiting` | vm-web-01 | nginx: 5 req/min pe `/wp-login.php`, `/wp-admin/`, `/xmlrpc.php`, `/api/` |
| `fail2ban` | toate Linux | Auto-ban IP dupa 5 incercari esuate SSH, ban 1 ora; ignoreip 10.10.12.0/24 (mgmt subnet) |
| `ssh_hardening` | toate Linux | curve25519 KEX, ChaCha20/AES-256-GCM, MACs ETM, AllowUsers azureadmin |
| `modsecurity` | vm-web-01 | ModSecurity On, OWASP CRS 3.2.1, paranoia level 1, excluderi WordPress |
| `mysql_hardening` | vm-db-01 | Stergere useri anonimi, test DB, `local_infile=OFF`, TDE InnoDB |

**Output generat de fiecare demo:**

| Fisier | Continut |
|--------|----------|
| `logs/security-demos/demo-N-*-TIMESTAMP.html` | Raport HTML cu BEFORE/AFTER/DIFF, colorat, pentru comisie |
| `logs/security-demos/*-before.txt` | Starea initiala (vulnerabila) |
| `logs/security-demos/*-after.txt` | Starea dupa hardening (protejata) |
| `logs/security-demos/security-demo-report-*.html` | Raport master (toate hardeningurile) |

---

## Pas 9: Monitorizare (health check scripts)

```bash
ansible-playbook playbooks/6-monitoring.yml
```

**Ce face:**
- Deployeaza `check-health.sh` (Linux) / `check-health.ps1` (Windows) pe fiecare VM
- Linux: cron job la 5 minute, loguri via `logger -t mediasrl-health`
- Windows: Scheduled Task la 5 minute, loguri via `Write-EventLog`
- Azure Monitor Agent (instalat de Bicep) colecteaza logurile prin DCR → Log Analytics → KQL Alert Rules

**Servicii monitorizate per VM:**

| VM | Servicii | Porturi |
|----|----------|---------|
| vm-jmp-01 | sshd, xrdp | 22, 3389 |
| vm-web-01 | nginx | 80, 443 |
| vm-app-01 | nginx | 8080 |
| vm-cms-01 | nginx, php8.1-fpm, postfix | 80, 25 |
| vm-db-01 | MySQL80 | 3306 |
| vm-fs-01 | LanmanServer | 445 |

---

## Pas 10: Testare si validare

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

### Verificare Ansible (de pe jumphost)

```bash
# Verificare servicii pe toate VM-urile
ansible-playbook playbooks/3-verify.yml
```

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
# Dupa, reconecteaza RDP si ruleaza playbook-urile (Pasii 5-9)
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

### Prezentare generală pipeline-uri

| Pipeline | Fișier | Trigger | Scop |
|----------|--------|---------|------|
| Packer Build | `pipelines/packer-build.yml` | Manual | Construiește imagini golden (3 imagini, selectabile) |
| Bicep Deploy | `pipelines/bicep-deploy.yml` | **Auto** (push pe `master`, modificări `bicep/*`) | Validate → What-If → Deploy (cu aprobare manuală pe `production`) |
| Ansible Configure | `pipelines/ansible-configure.yml` | Manual | Rulează playbook-uri pe jumphost (selecție playbook + tags) |

**Resurse Azure DevOps necesare:**

| Resursă | Nume | Tip |
|---------|------|-----|
| Service Connection | `azure-service-connection` | Workload Identity Federation |
| Variable Group | `mediasrl-secrets` | Library → Variable Group |
| Environment | `production` | Cu approval gate pentru stage Deploy |
| Agent Pool | `Default` | Self-hosted agent Windows (mașina administratorului) |

---

### Pas 1 — Cerințe preliminare pe mașina Windows a administratorului

Agentul self-hosted rulează pe mașina Windows a administratorului și execută toate comenzile pipeline-ului (az cli, bicep, git). Sunt necesare:

#### 1.1 Instalare Git for Windows

Descarcă și instalează de la [git-scm.com](https://git-scm.com/download/win). Verifică:

```powershell
git --version
# git version 2.x.x.windows.x
```

#### 1.2 Instalare Azure CLI

```powershell
# Descarcă și instalează Azure CLI (MSI)
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
Remove-Item AzureCLI.msi

# Verifică
az --version
# azure-cli 2.x.x
```

#### 1.3 Instalare și activare extensie Bicep

```powershell
# Instalează extensia Bicep în Azure CLI
az bicep install

# Verifică
az bicep version
# Bicep CLI version 0.x.x

# Actualizare Bicep (când e cazul)
az bicep upgrade
```

#### 1.4 Instalare PowerShell 7+ (dacă nu e instalat)

Pipeline-ul folosește `scriptType: 'ps'` → necesită PowerShell 7+:

```powershell
# Verifică versiunea curentă
$PSVersionTable.PSVersion
# Major trebuie să fie 7

# Dacă e 5.x, instalează PowerShell 7:
winget install Microsoft.PowerShell
```

---

### Pas 2 — Creare Service Connection (Workload Identity Federation)

Service Connection-ul permite pipeline-ului să se autentifice la Azure **fără secret/parolă** — folosește Workload Identity Federation (OIDC), recomandat față de Service Principal cu secret.

1. **Azure DevOps** → Proiectul MEDIA SRL → **Project Settings**
2. **Pipelines** → **Service connections** → **New service connection**
3. **Azure Resource Manager** → **Next**
4. **Workload Identity Federation (automatic)** → **Next**
5. Se completează:
   - **Subscription:** selectează subscripția Azure
   - **Resource group:** gol (permisiuni la nivel de subscripție, necesare pentru `az deployment sub create`)
   - **Service connection name:** `azure-service-connection` 
   - Bifează **Grant access permission to all pipelines**
6. Click **Save**

> **Notă:** La creare, Azure DevOps înregistrează automat o Managed Identity/App Registration în Azure AD și configurează federated credentials. Nu se generează niciun secret.

**Verificare permisiuni:** Service Connection-ul creat trebuie să aibă rolul **Contributor** pe subscripție (pentru `az deployment sub create`). Se poate verifica în Azure Portal → Subscripție → Access control (IAM):

```powershell
# Identifică Service Principal-ul creat de Azure DevOps
az ad sp list --display-name "<numele-conexiunii>" --query "[].appId" -o tsv

# Verifică rolurile (trebuie Contributor la nivel de subscripție)
az role assignment list --assignee <appId> --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

---

### Pas 3 — Creare Variable Group `mediasrl-secrets`

Variable Group-ul stochează variabilele secrete accesate de toate pipeline-urile.

1. **Azure DevOps** → **Pipelines** → **Library** → **+ Variable group**
2. **Name:** `mediasrl-secrets`
3. Adaugă variabilele:

| Variabilă | Valoare | Secret |
|-----------|---------|--------|
| `AZURE_SUBSCRIPTION_ID` | ID-ul subscripției Azure | Nu |
| `AZURE_TENANT_ID` | ID-ul tenant-ului Azure AD | Nu |
| `ANSIBLE_VAULT_PASSWORD` | Parola Ansible Vault | **Da** |
| `KV_NAME` | `kv-mediasrl-productie` | Nu |
| `GALLERY_RG` | `rg-mediasrl-packer-swedencentral` | Nu |

4. **Pipelines permissions** → se adaugă pipeline-urile care au acces
5. **Save**

---

### Pas 4 — Creare Environment `production` cu Approval Gate

Environment-ul `production` blochează stage-ul **Deploy** al pipeline-ului Bicep până la aprobare manuală explicită.

1. **Azure DevOps** → **Pipelines** → **Environments** → **New environment**
2. Completează:
   - **Name:** `production`
   - **Description:** `Mediu producție SC MEDIA SRL — necesită aprobare înainte de deploy`
   - **Resource:** None
3. **Create**
4. În environment-ul creat → **...** (meniu) → **Approvals and checks** → **+** → **Approvals**
5. Se configurează:
   - **Approvers:** adaugă utilizatorul administratorului (sau grupul)
   - **Allow approvers to approve their own runs:** Da
   - **Timeout:** 1440 minute (24 ore)
6. **Create**

> **Comportament:** Când pipeline-ul ajunge la stage-ul `Deploy`, se oprește și trimite notificare pe email. Aprobarea se face din Azure DevOps UI → Pipelines → Run → **Review** → **Approve**.

---

### Pas 5 — Instalare Self-Hosted Agent Windows

Agentul self-hosted rulează pe mașina Windows a administratorului și execută job-urile din pipeline. Pipeline-ul Bicep folosește `pool: name: 'Default'`.

#### 5.1 Descărcare și pregătire agent

1. **Azure DevOps** → **Project Settings** → **Pipelines** → **Agent pools**
2. Click pe pool-ul **Default** → **Agents** → **New agent**
3. Selectează **Windows** → **x64**
4. Copiază link-ul de descărcare SAU rulează direct:

```powershell
# Creează directorul agentului
New-Item -ItemType Directory -Path "C:\agent" -Force
Set-Location C:\agent

# Descarcă agentul (versiunea curentă — verifică link-ul din Azure DevOps UI)
Invoke-WebRequest -Uri "https://vstsagentpackage.azureedge.net/agent/4.248.0/vsts-agent-win-x64-4.248.0.zip" `
                  -OutFile "agent.zip" -UseBasicParsing

# Extrage
Expand-Archive -Path "agent.zip" -DestinationPath "." -Force
Remove-Item "agent.zip"
```

> **Important:** Folosește link-ul generat de Azure DevOps UI (Pas 2 de mai sus) — conține întotdeauna ultima versiune stabilă.

#### 5.2 Configurare agent

```powershell
Set-Location C:\agent

# Rulează configurarea (interactiv)
.\config.cmd
```

Cnfigurare:

```
Enter server URL                    > https://dev.azure.com/valentintita12
Enter authentication type (PAT)    > PAT
Enter personal access token        > <PAT-ul generat la Pas 5.3>
Enter agent pool                   > Default
Enter agent name                   > agent-mediasrl-win
Enter work folder                  > _work   [Enter pentru implicit]
```

#### 5.3 Generare PAT (Personal Access Token) pentru configurare

PAT-ul e folosit **doar la configurare** — după înregistrare, agentul folosește un token intern Azure DevOps.

1. **Azure DevOps** → click avatar (dreapta sus) → **Personal access tokens**
2. **New Token:**
   - **Name:** `agent-setup-token`
   - **Expiration:** 30 zile (suficient pentru configurare)
   - **Scopes:** **Agent Pools (Read & manage)**
3. Copiază token-ul → folosește-l la `config.cmd` → poți să-l revoci după configurare

#### 5.4 Instalare ca serviciu Windows (pornire automată)

```powershell
Set-Location C:\agent

# Instalează agentul ca serviciu Windows
.\svc.cmd install

# Pornește serviciul
.\svc.cmd start

# Verifică starea
.\svc.cmd status
# Expected output: vsts.agent.<org>.<pool>.<name>  Running
```

Serviciul Windows se numește `vsts.agent.<organizatie>.Default.agent-mediasrl-win` și pornește automat la boot, fără logare utilizator.

#### 5.5 Verificare agent online

1. **Azure DevOps** → **Project Settings** → **Agent pools** → **Default** → **Agents**
2. Agentul `agent-mediasrl-win` trebuie să apară cu status **Online** (cerc verde)

```powershell
# Test rapid — verifică că agentul e activ
Get-Service | Where-Object { $_.Name -like "vsts.agent*" } | Select-Object Name, Status, StartType
# Expected: Name=vsts.agent.*, Status=Running, StartType=Automatic
```

#### 5.6 Verificare dependențe din perspectiva agentului

```powershell
# Rulează ca utilizatorul sub care rulează serviciul (NT AUTHORITY\SYSTEM sau contul configurat)
# Deschide PowerShell ca Administrator și verifică:

az --version        # Azure CLI accesibil în PATH
az bicep version    # Bicep extension instalată
git --version       # Git accesibil în PATH

# Test autentificare (agentul folosește Service Connection, nu contul tău personal)
az login --use-device-code   # Doar pentru test manual, nu e necesar pentru pipeline
```

> **Atenție PATH:** Dacă `az` sau `git` nu se găsesc, verifică că au fost instalate pentru **All Users** și că `C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin` și `C:\Program Files\Git\cmd` sunt în PATH-ul **System** (nu doar User).

```powershell
# Adaugă în PATH System dacă lipsesc
$syspath = [Environment]::GetEnvironmentVariable("Path", "Machine")
[Environment]::SetEnvironmentVariable("Path", "$syspath;C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;C:\Program Files\Git\cmd", "Machine")

# Repornește serviciul agentului ca să preia noul PATH
.\svc.cmd stop
.\svc.cmd start
```

---

### Pas 6 — Import pipeline Bicep în Azure DevOps

1. **Azure DevOps** → **Pipelines** → **New pipeline**
2. **Where is your code?** → **Azure Repos Git** (sau GitHub, dacă repo-ul e acolo)
3. Selectează repository-ul proiectului
4. **Configure your pipeline** → **Existing Azure Pipelines YAML file**
5. **Branch:** `master` | **Path:** `/pipelines/bicep-deploy.yml`
6. Click **Continue** → **Save** (NU Run — primul run se face automat la primul push)

**Acordă permisiuni la prima rulare:** La prima execuție, pipeline-ul va cere permisiune să acceseze:
- Service Connection `azure-service-connection` → **Permit**
- Variable Group `mediasrl-secrets` → **Permit**
- Environment `production` → **Permit**

---

### Pas 7 — Funcționare trigger automat

Pipeline-ul `bicep-deploy.yml` se declanșează automat la orice `git push` pe branch-ul `master` care modifică fișiere din:
- `bicep/*` — orice fișier Bicep sau parametri
- `scripts/finalize-jumphost.sh` — scriptul de finalizare jumphost

**Flux complet după un push:**

```
git add bicep/main.bicep
git commit -m "update: mareste dimensiunea vm-web-01 la B4ls_v2"
git push origin master
        │
        ▼
Azure DevOps detectează push-ul (webhook)
        │
        ▼
Stage: Validate (automat, ~3 min)
  ├── Bicep Build (syntax check)
  ├── az deployment sub validate
  └── az deployment sub what-if (preview modificări)
        │
        ▼ (dacă Validate trece)
Stage: Deploy — BLOCAT (așteaptă aprobare)
  └── Email notificare → administratorul aprobă în DevOps UI
        │
        ▼ (după aprobare)
  └── az deployment sub create → infrastructura actualizată
```

**Pull Requests (validare fără deploy):**
La deschiderea unui PR spre `master`, rulează doar stage-ul **Validate** — util pentru review înainte de merge.

---

### Pas 8 — Troubleshooting agent

#### Agentul apare Offline în Azure DevOps

```powershell
# Verifică serviciul
Get-Service | Where-Object { $_.Name -like "vsts.agent*" }

# Dacă Stopped:
Set-Location C:\agent
.\svc.cmd start

# Verifică log-urile agentului
Get-Content "C:\agent\_diag\Agent_*.log" -Tail 50
```

#### Pipeline eșuează cu "No hosted agents available"

Înseamnă că pool-ul `Default` nu are agenți online. Verifică agentul și repornește serviciul.

#### `az` sau `git` nu se găsesc în pipeline

```powershell
# Verifică PATH-ul System (nu User — serviciul rulează ca SYSTEM)
[Environment]::GetEnvironmentVariable("Path", "Machine")

# Adaugă manual și repornește serviciul agentului
```

#### Eroare "The user is not authorized to query the secret" (Key Vault)

Service Connection-ul (`azure-service-connection`) nu are permisiuni pe Key Vault. Adaugă rolul `Key Vault Secrets User` pentru Service Principal în Azure Portal.

#### Stage Deploy nu primește aprobare (timeout)

Timeout-ul implicit e 1440 minute (24h). Verifică email-ul pentru notificarea de aprobare sau accesează direct:
**Azure DevOps** → **Pipelines** → **Runs** → Run-ul respectiv → **Review** → **Approve**

---

### Referință rapidă — comenzi utile agent

```powershell
Set-Location C:\agent

.\svc.cmd status    # Verifică starea serviciului
.\svc.cmd start     # Pornește agentul
.\svc.cmd stop      # Oprește agentul
.\svc.cmd restart   # Repornește agentul
.\svc.cmd uninstall # Dezinstalează serviciul (păstrează configurarea)

# Reconfigurare completă (dacă organizația/URL-ul se schimbă)
.\config.cmd remove  # Elimină înregistrarea din Azure DevOps
.\config.cmd         # Reînregistrează agentul
```

---

SC MEDIA SRL — Deployment Guide · furnizor: SC IT SECURITY SRL · 2026
