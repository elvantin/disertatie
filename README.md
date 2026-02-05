# Infrastructure Cloud Automatizată - SC MEDIA SRL

**Proiect disertație Master**: Proiectarea, implementarea și securizarea unei infrastructuri cloud automatizate în Microsoft Azure utilizând Bicep, Packer și Ansible

---

## 📋 Arhitectură

### **Infrastructură Finală (5 VMs):**

| VM | OS | Rol | Subnet | IP Public |
|----|----|----|--------|-----------|
| **vm-jmp-01** | Rocky Linux 9 + GNOME + xRDP | Jumphost / Ansible Control Node | mgmt | ✅ |
| **vm-fs-01** | Windows Server 2022 | File Server (SMB shares) | prod | ❌ |
| **vm-web-01** | Rocky Linux 9 | Web Server (nginx) | prod | ❌ |
| **vm-app-01** | Rocky Linux 9 | Application Server | prod | ❌ |
| **vm-cms-01** | Rocky Linux 9 | CMS (WordPress + MySQL + Postfix) | prod | ❌ |

### **Networking:**
- **VNet:** 10.10.0.0/20
- **Subnets:**
  - Management: 10.10.12.0/24
  - Production: 10.10.10.0/24
  - Development: 10.10.11.0/24
- **NSGs:** 3 Network Security Groups (mgmt, prod, dev)
- **Access:** RDP către jumphost (port 3389), SSH între VMs

---

## 🛠️ Tehnologii Utilizate

| Component | Tehnologie | Scop |
|-----------|------------|------|
| **IaC** | Azure Bicep | Definirea și deployment infrastructure |
| **Golden Images** | HashiCorp Packer | Template-uri hardened pentru Rocky Linux & Windows |
| **Config Management** | Ansible | Configurare post-deployment și orchestrare |
| **CI/CD** | Azure DevOps | Automation pipelines |
| **Monitoring** | Azure Monitor + Log Analytics | Observability (free tier) |
| **Security** | Azure Policy + CIS Benchmarks | Governance și hardening |

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
│       └── policy.bicep
├── packer/
│   ├── rocky-linux/                    # Rocky Linux 10 template
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
│       ├── jumphost/                   # Rocky Linux GUI + xRDP + Ansible
│       ├── fileserver/                 # Windows File Server
│       ├── common/                     # Baseline config
│       ├── nginx/                      # Web server
│       ├── wordpress/                  # CMS + MySQL local
│       ├── postfix/                    # Mail server
│       └── hardening/                  # CIS Benchmarks
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
az bicep install

# Packer
winget install HashiCorp.Packer
```

### **2. Login to Azure**

```powershell
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### **3. Deploy Infrastructure (Bicep)**

```powershell
cd bicep

# Validare
az deployment sub validate `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam

# Deployment
az deployment sub create `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name deploy-mediasrl-productie
```

### **4. Configure VMs (Ansible)**

```bash
# Din jumphost (vm-jmp-01) după conectare via RDP
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
✅ **NSG Rules** - Segmentare rețea, deny-all implicit
✅ **CIS Benchmarks** - Hardening Linux & Windows
✅ **SSH Key-based Auth** - Fără password pentru Linux
✅ **Key Vault** - Stocare securizată secrets
✅ **Audit Logging** - auditd (Linux) + Event Log (Windows)
✅ **Disable SMBv1** - File server security
✅ **TLS 1.2+** - Toate comunicațiile criptate

---

## 📊 Monitorizare

- **Azure Monitor** - Free tier (5 GB/month)
- **Log Analytics Workspace** - Centralizare logs
- **VM Extensions** - MMA (Windows) + OMS Agent (Linux)
- **Metrics** - CPU, memory, disk, network

---

## 🎯 Use Case: SC MEDIA SRL

**Context:** SC MEDIA SRL (companie PR & Marketing) contractează SC IT SECURITY SRL pentru migrarea infrastructure în cloud Azure.

**Cerințe:**
- Infrastructure as Code (reproductibilitate)
- Golden images hardened (security)
- Configuration management (Ansible)
- File server (shared folders pentru echipă)
- Web platform (WordPress pentru portfolio)
- Mail server (comunicare internă)
- Jumphost Linux cu GUI pentru DevOps engineers

**Rezultat:** Infrastructură fully automated, secure, monitorizată, cost-effective.

---

## 📚 Documentație Detaliată

- [Bicep Deployment Guide](bicep/README.md)
- [Packer Templates](packer/README.md)
- [Ansible Roles](ansible/README.md)
- [Azure DevOps Pipelines](pipelines/README.md)

---

## 👤 Autor

**SC IT SECURITY SRL** - Proiect disertație Master
**Anul:** 2026
**Universitate:** [Numele universității]

---

## 📝 Licență

Acest proiect este destinat exclusiv pentru scopuri academice (disertație master).
