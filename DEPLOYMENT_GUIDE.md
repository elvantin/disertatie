# Deployment Guide — Infrastructura SC MEDIA SRL

**Ultima actualizare:** 2026-06-12

---

## Prezentare generala

Infrastructura SC MEDIA SRL se deployeaza in 4 etape principale:

1. **Bootstrap Key Vault** — creeaza KV persistent si populeaza secretele (o singura data)
2. **Packer** — construieste imaginile golden Ubuntu si Windows (o singura data sau la actualizare)
3. **Bicep** — deployeaza infrastructura Azure (VNet, NSG, VMs, KV, monitoring etc.)
4. **Ansible** — configureaza VM-urile (roluri: nginx, wordpress, mysql, fileserver, hardening)

---

## Arhitectura

| VM | OS | Rol | Subnet | IP |
|----|-----|-----|--------|----|
| vm-jmp-01 | Ubuntu 22.04 (jumphost image) | Jumphost: XFCE + xRDP + Ansible control node | snet-mgmt | Public persistent |
| vm-web-01 | Ubuntu 22.04 (base image) | nginx reverse proxy + SSL/TLS | snet-prod | Public persistent |
| vm-app-01 | Ubuntu 22.04 (base image) | Application server (port 8080) | snet-prod | Privat |
| vm-cms-01 | Ubuntu 22.04 (base image) | WordPress + PHP-FPM + Postfix | snet-prod | Privat |
| vm-db-01  | Windows Server 2022 | MySQL Community Server 8.0 | snet-prod | Privat |
| vm-fs-01  | Windows Server 2022 | File Server (SMB) | snet-prod | Privat |

---

## Cerinte preliminare

Pe masina locala (Windows):

- **Azure CLI** — `winget install Microsoft.AzureCLI`
- **Packer** — `winget install HashiCorp.Packer`
- **Bicep** — inclus in Azure CLI (`az bicep install`)
- **SSH client** — inclusiv in Windows 10/11 by default
- Autentificare: `az login`

---

## Pas 0: Bootstrap Key Vault (O SINGURA DATA)

Inainte de orice deployment, creeaza Key Vault-ul persistent si populeaza secretele de infrastructura.

```powershell
.\scripts\0-bootstrap-keyvault.ps1
```

Ce face:
- Creeaza `rg-mediasrl-persistent` (daca nu exista)
- Deploya `kv-mediasrl-persistent` via Bicep
- Solicita parolele de infrastructura (CSV sau interactiv)
- Stocheaza secretele in KV (rescrie fortat la fiecare rulare)
- Genereaza automat `ansible-vault-password` (GUID random)

**Secrete stocate:**

| Secretul KV | Descriere |
|-------------|-----------|
| `vm-admin-password` | Parola admin pentru toate VM-urile |
| `mysql-root-password` | Parola root MySQL |
| `mysql-wordpress-password` | Parola user MySQL pentru WordPress |
| `mysql-monitoring-password` | Parola user MySQL pentru monitoring |
| `mysql-api-password` | Parola user MySQL pentru API |
| `wordpress-admin-password` | Parola admin WordPress |
| `ansible-vault-password` | Parola vault Ansible (auto-generata) |

---

## Pas 1: Construire imagini Packer

Imaginile golden trebuie construite INAINTE de deployment-ul Bicep (cu `useMarketplaceImages = false`).

```powershell
.\scripts\1-build-packer-images.ps1
```

**Imagini create in `gal_mediasrl`:**

| Image Definition | Continut |
|-----------------|----------|
| `imgdef-ubuntu2204` | Ubuntu 22.04 base: update, pachete comune, SSH hardening |
| `imgdef-ubuntu2204-jumphost` | Ubuntu 22.04 + XFCE + xRDP + Ansible + Azure CLI + VS Code |
| `imgdef-winserver2022` | Windows Server 2022 + WinRM pre-configurat pentru Ansible |

**Durata estimata:** 10-30 minute per imagine

---

## Pas 2: Deploy infrastructura Bicep

```powershell
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
```

Scriptul:
1. Detecteaza automat IP-ul public local si il adauga la whitelist NSG
2. Ruleaza `az deployment sub validate`
3. Afiseaza `az deployment sub what-if` (previzualizare modificari)
4. Cere confirmare inainte de creare
5. Ruleaza `az deployment sub create`
6. Afiseaza IP-urile publice si pasii urmatori

**Durata estimata:** 8-15 minute

**Ce se creeaza:**

- 2 Resource Groups: `rg-mediasrl-productie-swedencentral` + `rg-mediasrl-persistent`
- 1 VNet (10.10.0.0/20) cu 3 subnets + 3 NSG-uri
- 1 Key Vault + 1 Log Analytics Workspace
- Azure Policies (subscription scope)
- 6 VM-uri + NICs + OS Disks
- 2 IP-uri publice persistente (jumphost + webserver)
- WinRM configurat automat pe Windows VMs via `runCommands`

**Nota privind imaginile:**

| Parametru | Comportament |
|-----------|-------------|
| `useMarketplaceImages = false` | Foloseste imagini din `gal_mediasrl` (recomandat) |
| `useMarketplaceImages = true` | Foloseste imagini marketplace + CSE bootstrap la boot |

### Verificare

```powershell
az vm list -g rg-mediasrl-productie-swedencentral -o table `
  --query "[].{Name:name, State:powerState, OS:storageProfile.osDisk.osType}"

az network public-ip list -g rg-mediasrl-persistent -o table `
  --query "[].{Name:name, IP:ipAddress}"
```

---

## Pas 3: Deploy Ansible pe jumphost

Copiaza directorul `ansible/` pe jumphost si ruleaza configurarea initiala:

```powershell
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod
```

Ce face:
1. Copiaza `ansible/` pe jumphost via SCP
2. Seteaza permisiunile si activeaza inventarul pentru mediul ales
3. Ruleaza `ansible/scripts/create-ansible-vault.sh` via SSH:
   - Se autentifica in Azure via Managed Identity
   - Preia secretele din `kv-mediasrl-persistent`
   - Creeaza `group_vars/all/vault.yml` encriptat AES-256
   - Salveaza parola vault la `~/.vault-pass` (chmod 600)

**Parametri:**

```powershell
.\scripts\3-deploy-ansible-to-jumphost.ps1 `
  -JumphostIP 4.223.228.18 `
  -Environment prod
```

---

## Pas 4: Conectare la Jumphost

### Obtine IP-ul public

```powershell
az network public-ip show -g rg-mediasrl-persistent -n pip-vm-jmp-01 --query ipAddress -o tsv
```

### Conectare RDP

```powershell
mstsc /v:<IP_JUMPHOST>
```

Credentiale:
- Username: `azureadmin`
- Password: secretul `vm-admin-password` din `kv-mediasrl-persistent`

---

## Pas 5: Configurare cu Ansible (din Jumphost)

Dupa conectare RDP la vm-jmp-01 (Ubuntu cu desktop XFCE), deschide un terminal:

```bash
cd ~/ansible

# Verifica conectivitate
ansible all -m ping                    # Linux VMs (SSH)
ansible windows -m win_ping            # Windows VMs (WinRM)

# Deploy complet
ansible-playbook playbooks/2-site.yml

# Deploy selectiv
ansible-playbook playbooks/2-site.yml --tags common
ansible-playbook playbooks/2-site.yml --tags webserver
ansible-playbook playbooks/2-site.yml --tags cms
ansible-playbook playbooks/2-site.yml --tags database
ansible-playbook playbooks/2-site.yml --tags fileserver
ansible-playbook playbooks/2-site.yml --tags hardening
```

---

## Pas 6: Testare

```powershell
.\scripts\4-test-infrastructure.ps1
```

**Categorii testate:**

| Categorie | Teste |
|-----------|-------|
| Azure Resources | Resource Groups, VNet, NSG-uri, Key Vault, Log Analytics |
| Virtual Machines | 6 VM-uri exista si sunt Running |
| Security | Reguli NSG, Key Vault, taguri |
| Connectivity | SSH jumphost (22), RDP jumphost (3389), HTTPS webserver (443) |
| Idempotency | Bicep what-if verifica 0 modificari la re-deploy |
| Performance | Response time webserver, SSH connect time |

---

## Resurse create

```
Subscription (7a0255bf-...)
│
├── rg-mediasrl-persistent/
│   ├── pip-vm-jmp-01  (IP public static jumphost)
│   ├── pip-vm-web-01  (IP public static webserver, DNS: mediasrl)
│   └── kv-mediasrl-persistent  (secrete infrastructura)
│
├── rg-mediasrl-packer-swedencentral/
│   └── gal_mediasrl
│       ├── imgdef-ubuntu2204
│       ├── imgdef-ubuntu2204-jumphost
│       └── imgdef-winserver2022
│
└── rg-mediasrl-productie-swedencentral/
    ├── vnet-mediasrl-productie (10.10.0.0/20)
    │   ├── snet-prod (10.10.10.0/24) + nsg-prod
    │   ├── snet-dev  (10.10.11.0/24) + nsg-dev
    │   └── snet-mgmt (10.10.12.0/24) + nsg-mgmt
    ├── kv-mediasrl-productie
    ├── log-mediasrl-productie
    ├── vm-jmp-01, vm-web-01, vm-app-01, vm-cms-01, vm-db-01, vm-fs-01
    └── Azure Policies (subscription scope)
```

---

## Teardown / Recreare environment

```powershell
# Sterge DOAR environment-ul principal (KV persistent + IP-urile supravietuiesc)
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod

# Re-deploy:
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod
```

**Nu se sterg niciodata:** `rg-mediasrl-persistent` (IP-uri + KV secrete), `rg-mediasrl-packer-swedencentral` (gallery + imagini).

---

## Troubleshooting

### SSH: "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"

Apare dupa re-deployment (VM nou = chei host noi):

```powershell
ssh-keygen -R <IP>
```

### Ansible: conectivitate SSH

```bash
ansible all -m ping -vvv
ssh azureadmin@<private-ip>
```

### Ansible: conectivitate WinRM

```bash
ansible windows -m win_ping -vvv
# Check WinRM pe VM:
Test-WSMan -ComputerName localhost
winrm get winrm/config
```

Log WinRM bootstrap: `C:\Logs\mediasrl\winrm-bootstrap-*.log` pe Windows VMs.

### xRDP pe jumphost

```bash
sudo systemctl status xrdp
firewall-cmd --list-all
```

### Ansible Vault: re-creare

```bash
cd ~/ansible
bash scripts/create-ansible-vault.sh
```

### Vizualizare IP-uri VM-uri

```powershell
.\scripts\get-vm-ips.ps1
```

### Logs HTML

Toate scripturile genereaza loguri HTML in `logs/`:
```powershell
# Deschide ultimul log HTML
$latest = Get-ChildItem logs\*.html | Sort-Object LastWriteTime -Desc | Select-Object -First 1
Start-Process $latest.FullName
```

---

## Azure DevOps — Pipeline-uri CI/CD

| Pipeline | Fisier | Trigger | Scop |
|----------|--------|---------|------|
| Packer Build | `pipelines/packer-build.yml` | Manual | Construieste imagini golden |
| Bicep Deploy | `pipelines/bicep-deploy.yml` | Auto (push pe `master`) | Valideaza + deployeaza |
| Ansible Configure | `pipelines/ansible-configure.yml` | Manual | Ruleaza playbook-uri |

Self-hosted agent Windows, pool `Default`.

---

SC MEDIA SRL — Deployment Guide
