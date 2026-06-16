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

> **Nota executie demo-uri:** Demo-urile (Pas 8) deployeaza hardeningurile din playbook 5 in mod progresiv (BEFORE/AFTER). Daca nu se ruleaza demo-uri, se poate rula direct `playbooks/harden-security(daca_nu_rulez_demouri).yml` pentru a aplica toate hardeningurile deodata.

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
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml

# Sau individual cu tag-uri:
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml --tags rate_limiting
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml --tags fail2ban
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml --tags ssh_hardening
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml --tags modsecurity
ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml --tags mysql_hardening
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
