# Deployment Guide - Infrastructura SC MEDIA SRL

## Prezentare generala

Infrastructura SC MEDIA SRL este deployata in Azure folosind 3 instrumente, in aceasta ordine:

1. **Packer** - Construieste imaginile golden (Ubuntu base, Ubuntu jumphost, Windows Server)
2. **Bicep** - Deployeaza infrastructura Azure (VNet, NSG, VMs, Key Vault, etc.)
3. **Ansible** - Configureaza VM-urile (roluri: nginx, wordpress, mysql, fileserver, hardening, etc.)

---

## Arhitectura

| VM | OS | Rol | Subnet | IP |
|----|-----|-----|--------|----|
| vm-jmp-01 | Ubuntu 22.04 (jumphost image) | Jumphost: XFCE + xRDP + Ansible control node | snet-mgmt | Public (persistent) |
| vm-web-01 | Ubuntu 22.04 (base image) | Nginx reverse proxy + SSL/Let's Encrypt | snet-prod | Public (persistent) |
| vm-app-01 | Ubuntu 22.04 (base image) | Application server (Nginx port 8080) | snet-prod | Privat |
| vm-cms-01 | Ubuntu 22.04 (base image) | WordPress + MySQL local + Postfix | snet-prod | Privat |
| vm-db-01 | Windows Server 2022 | SQL Server (rezervat) | snet-prod | Privat |
| vm-fs-01 | Windows Server 2022 | File Server (SMB shares) | snet-prod | Privat |

```
DevOps Engineer (local)
  | (RDP:3389)
  v
vm-jmp-01 (Ubuntu + XFCE + Ansible)
  |-- (SSH) --> vm-web-01, vm-app-01, vm-cms-01
  |-- (WinRM) --> vm-db-01, vm-fs-01
  v
vm-web-01 (nginx reverse proxy)
  |-- proxy_pass --> vm-cms-01:80 (WordPress)
  |-- proxy_pass --> vm-app-01:8080 (API)
```

---

## Cerinte preliminare

Pe masina locala (Windows):

- **Azure CLI** - `winget install Microsoft.AzureCLI`
- **Packer** - `winget install HashiCorp.Packer`
- **Bicep** - inclus in Azure CLI (`az bicep install`)
- Autentificare: `az login`

---

## Pas 1: Construire imagini Packer

Imaginile golden trebuie construite INAINTE de a deploya infrastructura Bicep. Scriptul automatizat se ocupa de tot: creeaza Resource Group-ul dedicat, Azure Compute Gallery, Image Definitions si ruleaza Packer build.

```powershell
# Prima rulare (creeaza gallery + image definitions + construieste imaginile)
.\scripts\build-packer-images.ps1

# Rulari ulterioare (gallery exista deja, doar rebuild imagini)
.\scripts\build-packer-images.ps1 -SkipGallery

# Fara confirmare interactiva (construieste tot)
.\scripts\build-packer-images.ps1 -NoConfirm

# Doar o imagine specifica
.\scripts\build-packer-images.ps1 -SkipGallery  # apoi selectezi d/n per imagine
```

Scriptul:
- Verifica Azure CLI si Packer
- Creeaza `rg-mediasrl-packer-swedencentral` (daca nu exista)
- Creeaza gallery `gal_mediasrl` cu 3 image definitions
- Detecteaza automat versiunea urmatoare per imagine (auto-increment patch)
- Intreaba interactiv care imagini doresti sa le construiesti
- Salveaza output-ul complet in `logs/packer-*.log`

**Durata estimata:** 10-30 minute per imagine

**Imagini create:**

| Image Definition | Continut |
|------------------|----------|
| imgdef-ubuntu2204 | Ubuntu 22.04 base: update, pachete comune, SSH hardening, timezone |
| imgdef-ubuntu2204-jumphost | Ubuntu 22.04 jumphost: XFCE, xRDP, Ansible, Azure CLI, VS Code, Firefox |
| imgdef-winserver2022 | Windows Server 2022: WinRM configurat pentru Ansible, firewall port 5985 |

---

## Pas 2: Deploy infrastructura Bicep

Dupa ce imaginile Packer sunt publicate in gallery:

### 2a. Configureaza parametrii

Editeaza `bicep/parameters/prod.bicepparam`:
- Seteaza `useMarketplaceImages = false` (foloseste imagini din gallery)
- Verifica `imageVersion` sa corespunda cu versiunea publicata
- Verifica `adminIpAddress` (IP-ul tau pentru RDP/SSH access)
- Verifica `adminPassword` si `sshPublicKey`

### 2b. Deploy

```powershell
az deployment sub create --location swedencentral --template-file bicep/main.bicep --parameters bicep/parameters/prod.bicepparam --name deploy-mediasrl
```

**Durata estimata:** 8-12 minute

**Ce se creeaza:**
- 2 Resource Groups: `rg-mediasrl-productie-swedencentral` (principal) + `rg-mediasrl-persistent` (IP-uri publice)
- 1 VNet (10.10.0.0/20) cu 3 subnets (prod, dev, mgmt) + 3 NSG-uri
- 1 Key Vault + 1 Log Analytics Workspace
- 6 Azure Policies (la nivel de subscription)
- 6 VM-uri (din imagini gallery sau marketplace)
- 2 IP-uri publice persistente (jumphost + webserver)

**Nota:** Cand `useMarketplaceImages = true`, VM-urile sunt create din marketplace si se ruleaza Custom Script Extension la boot (bootstrap jumphost + WinRM). Cand `false`, imaginile gallery au deja bootstrap-ul baked in.

### 2c. Verificare

```powershell
# Lista VM-urilor
az vm list -g rg-mediasrl-productie-swedencentral -o table --query "[].{Name:name, State:powerState}"

# IP-urile publice persistente
az network public-ip list -g rg-mediasrl-persistent -o table --query "[].{Name:name, IP:ipAddress}"
```

---

## Pas 3: Conectare la Jumphost

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
- Password: cel din `prod.bicepparam`

---

## Pas 4: Configurare cu Ansible (din Jumphost)

Dupa conectare RDP la vm-jmp-01 (Ubuntu cu desktop XFCE):

```bash
# Navigheaza la workspace
cd ~/ansible

# Verifica conectivitate
ansible all -m ping                    # Linux VMs (SSH)
ansible windows -m win_ping            # Windows VMs (WinRM)

# Deploy complet (toate rolurile)
ansible-playbook playbooks/site.yml

# Deploy selectiv
ansible-playbook playbooks/site.yml --tags common          # pachete de baza
ansible-playbook playbooks/site.yml --tags webserver        # nginx pe vm-web-01
ansible-playbook playbooks/site.yml --tags cms              # WordPress pe vm-cms-01
ansible-playbook playbooks/site.yml --tags appserver        # nginx:8080 pe vm-app-01
ansible-playbook playbooks/site.yml --tags fileserver       # SMB shares pe vm-fs-01
ansible-playbook playbooks/site.yml --tags hardening        # CIS hardening
```

**Roluri Ansible disponibile:**

| Rol | Target | Descriere |
|-----|--------|-----------|
| common | Toate Linux | Pachete de baza, NTP, hardening SSH |
| jumphost | vm-jmp-01 | XFCE, xRDP, tools |
| nginx | vm-web-01 | Reverse proxy, SSL/Let's Encrypt |
| appserver | vm-app-01 | Nginx pe port 8080 |
| wordpress | vm-cms-01 | WordPress + PHP-FPM + config |
| mysql | vm-cms-01 | MySQL Server + databases |
| postfix | vm-cms-01 | Mail server local |
| sqlserver | vm-db-01 | SQL Server (Windows) |
| fileserver | vm-fs-01 | Windows File Server + SMB shares |
| hardening | Toate | CIS Benchmark hardening |

---

## Resurse create

```
Subscription (7a0255bf-...)
|
+-- rg-mediasrl-persistent/
|   +-- pip-vm-jmp-01 (IP public static jumphost)
|   +-- pip-vm-web-01 (IP public static webserver, DNS: mediasrl)
|
+-- rg-mediasrl-packer-swedencentral/
|   +-- gal_mediasrl (Azure Compute Gallery)
|       +-- imgdef-ubuntu2204 (v1.0.x)
|       +-- imgdef-ubuntu2204-jumphost (v1.0.x)
|       +-- imgdef-winserver2022 (v1.0.x)
|
+-- rg-mediasrl-productie-swedencentral/
|   +-- vnet-mediasrl-productie (10.10.0.0/20)
|   |   +-- snet-prod (10.10.10.0/24) + nsg-prod
|   |   +-- snet-dev (10.10.11.0/24) + nsg-dev
|   |   +-- snet-mgmt (10.10.12.0/24) + nsg-mgmt
|   +-- kv-mediasrl-productie (Key Vault)
|   +-- log-mediasrl-productie (Log Analytics)
|   +-- vm-jmp-01 (Ubuntu Jumphost)
|   +-- vm-web-01 (Ubuntu Nginx)
|   +-- vm-app-01 (Ubuntu App)
|   +-- vm-cms-01 (Ubuntu WordPress)
|   +-- vm-db-01 (Windows SQL)
|   +-- vm-fs-01 (Windows File Server)
|
+-- Azure Policies (subscription scope)
    +-- Allowed Locations (swedencentral, westeurope, northeurope)
    +-- Required Tags (environment, project, managed-by)
```

---

## Teardown / Recreare environment

```powershell
# Sterge DOAR environment-ul principal (IP-urile persistente supravietuiesc)
az group delete --name rg-mediasrl-productie-swedencentral --yes

# Imaginile Packer raman in gallery (rg-mediasrl-packer-swedencentral)
# IP-urile publice raman in rg-mediasrl-persistent

# Re-deploy:
az deployment sub create --location swedencentral --template-file bicep/main.bicep --parameters bicep/parameters/prod.bicepparam
```

---

## Troubleshooting

### Ansible: conectivitate SSH

```bash
# Test manual SSH
ssh azureadmin@vm-web-01

# Verifica inventarul dinamic Azure
ansible-inventory -i inventory/azure_rm.yml --list
```

### Ansible: conectivitate WinRM

```bash
# Test WinRM
ansible windows -m win_ping

# Debug manual
python3 -c "import winrm; s=winrm.Session('vm-fs-01',auth=('azureadmin','PASSWORD')); print(s.run_cmd('hostname'))"
```

### xRDP pe jumphost

```bash
sudo systemctl status xrdp
sudo ufw status
```

### Packer build esueaza

Verifica logurile din directorul `logs/`:
```powershell
Get-Content logs/packer-ubuntu-base-*.log -Tail 50
```

---

## Azure DevOps — Pipeline-uri CI/CD

### Prezentare generala

Proiectul include 3 pipeline-uri Azure DevOps YAML care automatizeaza fluxul de deployment:

| Pipeline | Fisier | Trigger | Scop |
|----------|--------|---------|------|
| Packer Build | `pipelines/packer-build.yml` | Manual | Construieste imagini golden si le publica in gallery |
| Bicep Deploy | `pipelines/bicep-deploy.yml` | Auto (push pe `master`) | Valideaza si deployeaza infrastructura Azure |
| Ansible Configure | `pipelines/ansible-configure.yml` | Manual | Ruleaza playbook-uri Ansible pe jumphost |

### Configurare Azure DevOps (pas cu pas)

#### Pas 1: Creare organizatie si proiect

1. Mergi la [dev.azure.com](https://dev.azure.com)
2. Creeaza organizatie (daca nu ai una)
3. Creeaza proiect nou: `SC-MEDIA-SRL` (visibility: Private, version control: Git)

#### Pas 2: Import repository

Push codul local in Azure Repos:
```powershell
git remote add azure https://dev.azure.com/{ORGANIZATIE}/SC-MEDIA-SRL/_git/SC-MEDIA-SRL
git push -u azure --all
```

#### Pas 3: Service Connection (`azure-service-connection`)

Project Settings → Service connections → New service connection → Azure Resource Manager:

| Camp | Valoare |
|------|---------|
| Identity type | App registration (automatic) |
| Credential | Workload identity federation (automatic) |
| Scope level | Subscription |
| Subscription | Selecteaza subscriptia (`7a0255bf-...`) |
| Resource group | **Lasa GOL** (acces la nivel de subscriptie) |
| Service connection name | `azure-service-connection` |
| Description | Service connection for SC MEDIA SRL infrastructure |
| Grant access to all pipelines | **Bifat** |

#### Pas 4: Variable Group (`mediasrl-secrets`)

Pipelines → Library → + Variable group:

| Variabila | Valoare | Secret (lock)? |
|-----------|---------|----------------|
| `adminPassword` | Parola admin VMs | Da |
| `sshPublicKey` | Cheia SSH publica | Da |

Pipeline permissions → Open access (permite tuturor pipeline-urilor).

#### Pas 5: Environment (`production`) cu Approval Gate

Pipelines → Environments → New environment:

| Camp | Valoare |
|------|---------|
| Name | `production` |
| Resource | None |

Dupa creare: ⋮ → Approvals and checks → + Approvals:
- Approvers: adauga-te pe tine
- Timeout: 1440 min (24h)
- Instructions: `Review What-If output before approving deployment.`

#### Pas 6: Secure File (`jumphost-ssh-key`)

Pipelines → Library → Secure files → + Secure file:
- Upload: cheia SSH **privata** (fisierul fara `.pub`)
- Name: `jumphost-ssh-key`
- Pipeline permissions → Authorize for all pipelines

#### Pas 7: Instalare Self-Hosted Agent (Windows)

Organizatiile Azure DevOps noi nu au agenti hosted gratuiti. Solutia: instalezi un agent local pe masina ta Windows care executa pipeline-urile.

**Nota:** Download-ul manual al ZIP-ului si unzip-ul sunt mai rapide decat folosirea PowerShell (Invoke-WebRequest este lent pe fisiere mari).

1. Descarca agentul: https://download.agent.dev.azure.com/agent/4.268.0/vsts-agent-win-x64-4.268.0.zip
2. Creeaza directorul `C:\agent` si extrage ZIP-ul acolo (click dreapta → Extract All)
3. Creeaza un **Personal Access Token (PAT)** in Azure DevOps:
   - User Settings (icon profil dreapta sus) → Personal Access Tokens
   - New Token → Name: `agent-token`, Scopes: **Agent Pools (Read & manage)** → Create
   - Copiaza token-ul generat (nu il vei mai putea vedea)
4. Deschide PowerShell in `C:\agent` si ruleaza:

```powershell
.\config.cmd --url https://dev.azure.com/{ORGANIZATIE} --auth pat
```

5. La prompts:
   - **Enter server URL:** (deja setat, apasa Enter)
   - **Enter authentication type:** (deja setat pe PAT, apasa Enter)
   - **Enter personal access token:** lipeste token-ul PAT
   - **Enter agent pool:** apasa Enter (Default)
   - **Enter agent name:** apasa Enter (numele calculatorului)
   - **Enter work folder:** apasa Enter (`_work`)
   - **Run agent as service? (Y/N):** N

6. Porneste agentul:

```powershell
.\run.cmd
```

Vei vedea `Listening for Jobs` — agentul este gata sa execute pipeline-uri.

**Nota:** Agentul trebuie sa fie pornit (`.\run.cmd`) de fiecare data cand vrei sa rulezi pipeline-uri. Pipeline-urile folosesc `pool: name: 'Default'` si `scriptType: 'ps'` (PowerShell) pentru compatibilitate cu agentul Windows.

#### Pas 8: Creare pipeline-uri (x3)

Pipelines → New pipeline → Azure Repos Git → repo → **Existing Azure Pipelines YAML file**:

| Pipeline | Path YAML | Nume recomandat |
|----------|-----------|-----------------|
| Packer | `/pipelines/packer-build.yml` | `Packer - Build Images` |
| Bicep | `/pipelines/bicep-deploy.yml` | `Bicep - Deploy Infrastructure` |
| Ansible | `/pipelines/ansible-configure.yml` | `Ansible - Configure VMs` |

#### Pas 9: Branch Policies pe `master`

Project Settings → Repos → Repositories → repo → Policies → branch `master`:

| Setare | Valoare |
|--------|---------|
| Require minimum reviewers | On, 1 reviewer |
| Allow requestors to approve own changes | Bifat |
| Check for comment resolution | Required |
| Build validation | + pipeline `Bicep - Deploy Infrastructure`, Trigger: Automatic |

### Utilizare pipeline-uri

```bash
# Packer: manual — Pipelines → Packer - Build Images → Run pipeline
#   Selecteaza imaginile dorite (buildUbuntuBase, buildJumphost, buildWindows)

# Bicep: automat la push pe master cu modificari in bicep/
#   Stage 1 (Validate) = automat, Stage 2 (Deploy) = necesita aprobare manuala

# Ansible: manual — Pipelines → Ansible - Configure VMs → Run pipeline
#   Alege playbook (site.yml, deploy-services.yml, etc.) si tags optional
```

---

## Pas 5: Testare si Validare (Etapa 6)

Proiectul include 2 suite de teste complementare: una rulata local (testeaza infrastructura Azure) si una rulata pe jumphost (testeaza serviciile VM-urilor).

### 5a. Teste infrastructura Azure (local, PowerShell)

Ruleaza de pe masina locala (Windows cu Azure CLI autentificat):

```powershell
# Ruleaza toate testele (inclusiv idempotency — dureaza 3-5 min)
.\scripts\test-infrastructure.ps1

# Ruleaza fara testul de idempotency (mai rapid, ~30 secunde)
.\scripts\test-infrastructure.ps1 -SkipIdempotency
```

**Ce testeaza (6 categorii):**

| Categorie | Teste |
|-----------|-------|
| Azure Resources | Resource Groups, VNet, subnets, NSG-uri, Key Vault, Log Analytics, Gallery, image definitions |
| Virtual Machines | 6 VM-uri exista si sunt Running, IP-uri publice persistente |
| Security | Reguli NSG (restrictie IP admin, deny all), Key Vault purge protection, Azure Policies, taguri |
| Connectivity | SSH (port 22) si RDP (port 3389) la jumphost, HTTP (80) si HTTPS (443) la webserver |
| Idempotency | Bicep what-if verifica 0 modificari la re-deploy (infrastructura stabila) |
| Performance | Response time webserver (<5s), SSH connect time (<10s) |

**Output:** Raport sumar cu contoare Pass/Fail/Warning per categorie.

### 5b. Teste servicii VM-uri (de pe jumphost, Ansible)

Conecteaza-te RDP la vm-jmp-01, deschide un terminal si ruleaza:

```bash
cd ~/ansible

# Ruleaza toate testele de servicii
ansible-playbook playbooks/test-services.yml

# Ruleaza doar anumite sectiuni (tags disponibile)
ansible-playbook playbooks/test-services.yml --tags linux_baseline
ansible-playbook playbooks/test-services.yml --tags jumphost_services
ansible-playbook playbooks/test-services.yml --tags webserver_tests
ansible-playbook playbooks/test-services.yml --tags connectivity
```

**Ce testeaza (10 sectiuni):**

| Sectiune | Target | Teste |
|----------|--------|-------|
| Linux Baseline | Toate Linux | SSH activ, OS version, timezone, root login dezactivat |
| Windows Baseline | Toate Windows | WinRM activ, OS version |
| Jumphost Services | vm-jmp-01 | Ansible, Azure CLI, xRDP, sshpass instalate |
| Webserver | vm-web-01 | Nginx activ, HTTP response code 200 |
| App Server | vm-app-01 | Nginx activ pe port 8080 |
| CMS Server | vm-cms-01 | PHP-FPM, MySQL, Postfix active |
| File Server | vm-fs-01 | SMB shares configurate |
| DB Server | vm-db-01 | MySQL/SQL Server activ |
| Cross-VM Connectivity | vm-jmp-01 | SSH catre Linux VMs, WinRM catre Windows VMs |
| Summary | - | Raport pass/fail per categorie |

**Nota:** Testele folosesc `failed_when: false` pentru serviciile care nu au fost inca configurate de Ansible. Acestea vor aparea ca Warning, nu ca Fail.

### 5c. Interpretare rezultate

- **PASS** — Testul a trecut cu succes
- **FAIL** — Ceva nu functioneaza corect, necesita investigare
- **WARNING** — Serviciu optional sau neconfigutat inca (nu e critic)

**Ordinea recomandata:**
1. Ruleaza mai intai `test-infrastructure.ps1` local (verifica ca Azure e OK)
2. Apoi conecteaza-te la jumphost si ruleaza `test-services.yml` (verifica serviciile)

---

SC MEDIA SRL - Deployment Guide
Ultima actualizare: 2026-02-16
