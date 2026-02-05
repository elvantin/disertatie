# 🚀 Deployment Guide - Infrastructure SC MEDIA SRL

## ✅ **Ce s-a modificat (Opțiunea B activată):**

### **Arhitectură Nouă:**

| Înainte | După |
|---------|------|
| vm-jmp-01: **Windows** Jumphost | vm-jmp-01: **Rocky Linux 9** + GNOME + xRDP + Ansible |
| vm-db-01: **Windows** Database (MySQL) | vm-fs-01: **Windows** File Server (SMB shares) |
| vm-cms-01: CMS (WordPress) | vm-cms-01: CMS (WordPress + **MySQL local**) |

### **Avantaje noua arhitectură:**
✅ **Ansible nativ** pe jumphost Linux (control node)
✅ **RDP access** prin xfreerdp către Windows File Server
✅ **SSH key distribution** automată între jumphost și Linux VMs
✅ **File Server** pentru shared folders (Marketing, IT, Backups)
✅ **Cost redus** (Rocky Linux free vs Windows Server license)

---

## 📋 **Fișiere Modificate:**

### **Bicep (Infrastructure):**
- ✏️ `bicep/main.bicep` - vm-jmp-01: Windows → Linux, vm-db-01 → vm-fs-01
- ✏️ `bicep/parameters/prod.bicepparam` - actualizat VM configs

### **Ansible (Configuration):**
- ✏️ `ansible/inventory/hosts.ini` - actualizat cu noua arhitectură
- ✏️ `ansible/playbooks/site.yml` - orchestrare pentru jumphost + fileserver
- ➕ `ansible/playbooks/setup-ssh-keys.yml` - distribuire SSH keys (NOU)
- ➕ `ansible/roles/jumphost/` - Rocky Linux GUI + xRDP + Ansible tools (NOU)
- ➕ `ansible/roles/fileserver/` - Windows File Server cu SMB shares (NOU)
- ✏️ `ansible/roles/wordpress/` - acum instalează MySQL local (nu remote)
- ✏️ `README.md` - documentație actualizată

---

## 🔧 **Deployment Steps:**

### **Pas 1: Cleanup VMs Existente (IMPORTANT!)**

Înainte de re-deployment, **șterge VM-urile existente** (sunt cu arhitectură veche):

```powershell
# Șterge toate VM-urile existente
az vm delete --resource-group rg-mediasrl-productie-swedencentral --ids $(az vm list -g rg-mediasrl-productie-swedencentral --query "[].id" -o tsv) --yes --no-wait

# Șterge NICs
az network nic list -g rg-mediasrl-productie-swedencentral --query "[].name" -o tsv | ForEach-Object { az network nic delete -g rg-mediasrl-productie-swedencentral -n $_ --no-wait }

# Șterge disks
az disk list -g rg-mediasrl-productie-swedencentral --query "[].name" -o tsv | ForEach-Object { az disk delete -g rg-mediasrl-productie-swedencentral -n $_ --yes --no-wait }

# Șterge Public IPs
az network public-ip list -g rg-mediasrl-productie-swedencentral --query "[].name" -o tsv | ForEach-Object { az network public-ip delete -g rg-mediasrl-productie-swedencentral -n $_ --no-wait }
```

**SAU mai rapid:**
```powershell
az group delete --name rg-mediasrl-productie-swedencentral --yes --no-wait
```

---

### **Pas 2: Deploy Infrastructure (Bicep)**

```powershell
cd bicep

# Deploy complet (cu noua arhitectură)
az deployment sub create `
  --location swedencentral `
  --template-file main.bicep `
  --parameters parameters/prod.bicepparam `
  --name deploy-mediasrl-final
```

**Durată estimată:** 8-10 minute

**Output așteptat:**
- 1 Resource Group
- 1 VNet + 3 Subnets + 3 NSGs
- 1 Key Vault
- 1 Log Analytics
- 6 Azure Policies
- **5 VMs:**
  - **vm-jmp-01** (Rocky Linux 9) - cu IP public
  - **vm-fs-01** (Windows Server 2022)
  - **vm-web-01, vm-app-01, vm-cms-01** (Rocky Linux 9)

---

### **Pas 3: Obține IP Public al Jumphost**

```powershell
$jumphostIP = az vm show -d -g rg-mediasrl-productie-swedencentral -n vm-jmp-01 --query publicIps -o tsv
Write-Host "Jumphost Public IP: $jumphostIP"
```

---

### **Pas 4: Conectare RDP la Jumphost**

**Windows:**
```powershell
mstsc /v:$jumphostIP
```

**Credențiale:**
- Username: `azureadmin`
- Password: `Str0ng_P@ssw0rd_2026!` (din prod.bicepparam)

---

### **Pas 5: Din Jumphost - Run Ansible**

După conectare RDP la vm-jmp-01 (Rocky Linux cu GNOME desktop):

```bash
# 1. Test connectivity
ansible all -m ping

# 2. Setup SSH keys (distribuie cheia jumphost către Linux VMs)
ansible-playbook playbooks/setup-ssh-keys.yml

# 3. Deploy complet (toate rolurile)
ansible-playbook playbooks/site.yml

# SAU deploy selectiv:
ansible-playbook playbooks/site.yml --tags jumphost,fileserver
ansible-playbook playbooks/site.yml --tags webserver,cms
ansible-playbook playbooks/site.yml --tags hardening
```

---

## 🔍 **Verificare Deployment:**

### **1. Verifică VM-urile create:**
```powershell
az vm list -g rg-mediasrl-productie-swedencentral --query "[].{Name:name, OS:storageProfile.osDisk.osType, State:powerState}" -o table
```

### **2. Verifică File Server (din jumphost):**
```bash
# RDP către Windows File Server
xfreerdp /v:vm-fs-01 /u:azureadmin /cert:ignore

# Sau test SMB shares
smbclient -L //vm-fs-01 -U azureadmin
```

### **3. Verifică Web Server:**
```bash
curl http://vm-web-01
```

### **4. Verifică CMS (WordPress + MySQL):**
```bash
curl http://vm-cms-01
ssh azureadmin@vm-cms-01 "sudo systemctl status mysqld"
```

---

## 📊 **Resurse Create:**

```
Subscription
├── rg-mediasrl-productie-swedencentral/
│   ├── vnet-mediasrl-productie (10.10.0.0/20)
│   ├── nsg-mgmt, nsg-prod, nsg-dev
│   ├── kv-mediasrl-productie (Key Vault)
│   ├── log-mediasrl-productie (Log Analytics)
│   ├── vm-jmp-01 (Rocky Linux + xRDP) - PUBLIC IP
│   ├── vm-fs-01 (Windows File Server)
│   ├── vm-web-01 (nginx)
│   ├── vm-app-01 (app server)
│   └── vm-cms-01 (WordPress + MySQL + Postfix)
└── Azure Policies (6 policies la nivel subscription)
```

---

## 🎯 **Access Pattern:**

```
DevOps Engineer Laptop
  ↓ (RDP:3389)
vm-jmp-01 (Rocky Linux GUI + Ansible)
  ├─ (SSH) → vm-web-01, vm-app-01, vm-cms-01
  └─ (RDP via xfreerdp) → vm-fs-01 (Windows File Server)
```

---

## 🔐 **Security Checklist:**

- ✅ NSG rules: deny-all implicit
- ✅ SSH key-based authentication (no passwords)
- ✅ Azure Policy enforcement (tags, locations, VM SKUs)
- ✅ CIS Benchmark hardening (auditd, kernel parameters, password policies)
- ✅ SMBv1 disabled on File Server
- ✅ Firewall enabled (firewalld Linux, Windows Firewall)
- ✅ SELinux enforcing (Linux VMs)

---

## 🐛 **Troubleshooting:**

### **Ansible connection issues:**
```bash
# Test SSH connectivity
ssh -i ~/.ssh/id_rsa azureadmin@vm-web-01

# Test WinRM (File Server)
ansible windows -m win_ping
```

### **RDP connection issues:**
```bash
# Verifică xRDP status pe jumphost
sudo systemctl status xrdp

# Verifică firewall
sudo firewall-cmd --list-all
```

### **File Server shares not accessible:**
```powershell
# Pe vm-fs-01
Get-SmbShare
Get-SmbServerConfiguration
```

---

## 📝 **Next Steps:**

1. ✅ Test complete deployment
2. ⏳ Build Packer golden images (Rocky 10 + Windows hardened)
3. ⏳ Switch to gallery images (set `useMarketplaceImages = false`)
4. ⏳ Implement Azure DevOps CI/CD pipelines
5. ⏳ Add SSL certificates (Let's Encrypt sau internal CA)

---

**Deployment Guide creat de:** SC IT SECURITY SRL
**Data:** 2026-02-05
**Status:** ✅ Ready for testing
