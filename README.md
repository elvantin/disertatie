# Infrastructure Cloud Automatizată - SC MEDIA SRL

**Proiect disertație Master**: Proiectarea, implementarea și securizarea unei infrastructuri cloud automatizate în Microsoft Azure utilizând Bicep, Packer și Ansible

---

## 📋 Arhitectură

### **Infrastructură Finală (6 VMs):**

| VM | OS | Rol | Subnet | IP Public | Specs |
|----|----|----|--------|-----------|-------|
| **vm-jmp-01** | Ubuntu 22.04 LTS + XFCE + xRDP | Jumphost / Ansible Control Node | mgmt | ✅ | D2s_v3 (2 vCPU, 8GB RAM, 64GB SSD) |
| **vm-fs-01** | Windows Server 2022 | File Server (SMB shares) | prod | ❌ | B2s (2 vCPU, 4GB RAM, 128GB SSD) |
| **vm-db-01** | Windows Server 2022 | Database Server (SQL Server) | prod | ❌ | B2s (2 vCPU, 4GB RAM, 128GB SSD) |
| **vm-web-01** | Ubuntu 22.04 LTS | Web Server (nginx) | prod | ❌ | B2s (2 vCPU, 4GB RAM, 32GB SSD) |
| **vm-app-01** | Ubuntu 22.04 LTS | Application Server | prod | ❌ | B2s (2 vCPU, 4GB RAM, 32GB SSD) |
| **vm-cms-01** | Ubuntu 22.04 LTS | CMS (WordPress + MySQL + Postfix) | prod | ❌ | B2s (2 vCPU, 4GB RAM, 32GB SSD) |

### **Networking:**
- **VNet:** 10.10.0.0/20
- **Subnets:**
  - Management: 10.10.12.0/24
  - Production: 10.10.10.0/24
  - Development: 10.10.11.0/24
- **NSGs:** 3 Network Security Groups (mgmt, prod, dev)
- **Access:** RDP către jumphost (port 3389), SSH între VMs (password auth pentru deployment, SSH keys via Ansible după)

---

## 🛠️ Tehnologii Utilizate

| Component | Tehnologie | Scop |
|-----------|------------|------|
| **IaC** | Azure Bicep | Definirea și deployment infrastructure |
| **Golden Images** | HashiCorp Packer | Template-uri hardened pentru Ubuntu & Windows |
| **Config Management** | Ansible | Configurare post-deployment și orchestrare |
| **CI/CD** | Azure DevOps | Automation pipelines |
| **Monitoring** | Azure Monitor + Log Analytics | Observability (free tier 5GB/month) |
| **Security** | Azure Policy + CIS Benchmarks | Governance și hardening |
| **Backup** | Azure Backup (Recovery Services Vault) | Daily backups, 14-day retention |

---

## 📂 Structura Proiectului

```
F:\My documents\Master\DISERTATIE\Project\IT\
├── bicep/
│   ├── main.bicep                      # Orchestrator principal
│   ├── parameters/
│   │   ├── prod.bicepparam             # Parametri producție
│   │   └── dev.bicepparam              # Parametri dezvoltare
│   └── modules/
│       ├── resource-group.bicep
│       ├── networking.bicep
│       ├── nsg.bicep
│       ├── compute.bicep
│       ├── keyvault.bicep
│       ├── monitoring.bicep
│       ├── policy.bicep
│       ├── backup.bicep                # Recovery Services Vault
│       └── backup-vm.bicep             # VM backup protection
├── packer/
│   ├── ubuntu-2204/                    # Ubuntu 22.04 LTS template
│   └── windows-server/                 # Windows Server 2022 template
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.ini                   # Static inventory
│   │   └── azure_rm.yml                # Dynamic Azure inventory
│   ├── playbooks/
│   │   ├── site.yml                    # Orchestrare completă
│   │   ├── setup-ssh-keys.yml          # Distribuire SSH keys
│   │   ├── deploy-services.yml
│   │   └── harden-all.yml
│   └── roles/
│       ├── common/                     # Baseline config
│       ├── nginx/                      # Web server
│       ├── wordpress/                  # CMS + MySQL local
│       ├── postfix/                    # Mail server
│       └── hardening/                  # CIS Benchmarks
├── scripts/
│   ├── bootstrap-jumphost.sh           # Jumphost bootstrap (xRDP + XFCE + Ansible)
│   └── README-jumphost-bootstrap.md    # Bootstrap documentation
├── pipelines/                          # Azure DevOps YAML
└── docs/                               # Documentație disertație
```

---

## 🚀 Quick Start

### **1. Prerequisites**

```powershell
# Azure CLI
winget install Microsoft.AzureCLI

# Bicep CLI
az bicep install && az bicep version

# Packer
winget install HashiCorp.Packer

# VS Code + Extensions
winget install Microsoft.VisualStudioCode
code --install-extension ms-azuretools.vscode-bicep
code --install-extension redhat.ansible
```

### **2. Login to Azure**

```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Get tenant ID and object ID for parameters
az account show --query tenantId -o tsv
az ad signed-in-user show --query id -o tsv
```

### **3. Accept Marketplace Terms (First Time Only)**

```powershell
# Ubuntu 22.04 LTS
az vm image terms accept --publisher canonical --offer ubuntu-22_04-lts --plan server

# Windows Server 2022
az vm image terms accept --publisher MicrosoftWindowsServer --offer WindowsServer --plan 2022-datacenter-azure-edition-smalldisk
```

### **4. Deploy Infrastructure (Bicep)**

```powershell
cd bicep

# Validare
az deployment sub validate `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

# Deployment
az deployment sub create `
  --name "mediasrl-prod-$(Get-Date -Format 'yyyyMMdd-HHmmss')" `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --verbose
```

### **5. Bootstrap Jumphost**

After deployment completes, bootstrap the jumphost with xRDP + XFCE + Ansible:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-jmp-01 `
  --command-id RunShellScript `
  --scripts '@scripts/bootstrap-jumphost.sh'
```

Wait ~12-15 minutes for bootstrap to complete (check `/tmp/jumphost-bootstrap-*.log` for progress).

### **6. Connect to Jumphost via RDP**

```powershell
# Get jumphost public IP
az vm list-ip-addresses `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-jmp-01 `
  --output table

# Connect via RDP
mstsc /v:<jumphost-public-ip>:3389
```

**Credentials:**
- Username: `azureadmin`
- Password: `Str0ng_P@ssw0rd_2026!` (change immediately after first login)

### **7. Configure VMs (Ansible)**

From jumphost (via RDP):

```bash
cd ~/ansible-workspace

# Test connectivity
ansible all -m ping

# Run complete deployment
ansible-playbook playbooks/site.yml
```

---

## 🔐 Securitate

### **Măsuri Implementate:**

✅ **Azure Policy** - Restricții region, VM SKUs, tag requirements
✅ **NSG Rules** - Segmentare rețea, deny-all implicit, allow only required ports
✅ **CIS Benchmarks** - Hardening Linux & Windows via Ansible
✅ **Password Auth at Deployment** - Toate VMs cu password pentru deployment inițial
✅ **SSH Key-based Auth** - Configurate via Ansible după deployment pentru Linux
✅ **Key Vault** - Stocare securizată secrets (TLS certificates, API keys)
✅ **Firewalld** - Firewall pe jumphost (replaces UFW)
✅ **Audit Logging** - auditd (Linux) + Windows Event Log
✅ **Disable SMBv1** - File server security
✅ **TLS 1.2+** - Toate comunicațiile criptate
✅ **AppArmor** - Ubuntu security framework (enabled by default)

---

## 📊 Monitorizare

- **Azure Monitor** - Free tier (5 GB/month)
- **Log Analytics Workspace** - Centralizare logs (retention: 31 days)
- **VM Extensions** - Deployment OMS Agent disabled during deployment (configured via Ansible post-deployment)
- **Metrics** - CPU, memory, disk, network
- **Backup** - Azure Backup daily at 1 AM, 14-day retention (currently disabled for testing, uncomment in main.bicep to enable)

---

## 🎯 Use Case: SC MEDIA SRL

**Context:** SC MEDIA SRL (companie PR & Marketing) contractează SC IT SECURITY SRL pentru migrarea infrastructure în cloud Azure.

**Cerințe:**
- Infrastructure as Code (reproductibilitate)
- Golden images hardened (security)
- Configuration management (Ansible)
- File server (shared folders pentru echipă)
- Database server (SQL Server pentru aplicații interne)
- Web platform (WordPress pentru portfolio)
- Mail server (comunicare internă)
- Jumphost Linux cu GUI (XFCE) pentru DevOps engineers

**Rezultat:** Infrastructură fully automated, secure, monitorizată, cost-effective.

---

## 🖥️ Jumphost Features

The jumphost (vm-jmp-01) is pre-configured with:

- **OS:** Ubuntu 22.04 LTS
- **Desktop:** XFCE (lightweight, optimized for RDP)
- **Remote Access:** xRDP (port 3389)
- **Browser:** Firefox ESR (from Mozilla Team PPA)
- **DevOps Tools:** Ansible, Azure CLI, VS Code, Git, htop, tmux, jq
- **RDP Client:** Remmina with pre-configured profiles for Windows VMs (vm-db-01, vm-fs-01)
- **Firewall:** firewalld (ports 22 SSH, 3389 RDP)
- **Workspace:** `~/ansible-workspace` for Ansible playbooks

---

## 📚 Documentație Detaliată

- [Jumphost Bootstrap Guide](scripts/README-jumphost-bootstrap.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Architecture Reference](ARCHITECTURE_QUICK_REFERENCE.md)
- [Ansible Roles](ansible/README.md)

---

## 🗂️ VM Configuration Status

| VM | Status | Notes |
|----|--------|-------|
| vm-jmp-01 | ✅ Deployed + Bootstrapped | Ubuntu 22.04 + XFCE + xRDP + Ansible |
| vm-web-01 | ✅ Deployed | Ubuntu 22.04 (nginx via Ansible) |
| vm-db-01 | ✅ Deployed | Windows Server 2022 (SQL Server via Ansible/DSC) |
| vm-fs-01 | 🚧 Disabled for testing | Windows Server 2022 (uncomment in parameters) |
| vm-app-01 | 🚧 Disabled for testing | Ubuntu 22.04 (uncomment in parameters) |
| vm-cms-01 | 🚧 Disabled for testing | Ubuntu 22.04 (uncomment in parameters) |

Currently testing with 3 VMs (jumphost, web, db). Uncomment remaining VMs in `bicep/parameters/prod.bicepparam` for full deployment.

---

## 👤 Autor

**SC IT SECURITY SRL** - Proiect disertație Master
**Anul:** 2026
**Universitate:** [Numele universității]

---

## 📝 Licență

Acest proiect este destinat exclusiv pentru scopuri academice (disertație master).
