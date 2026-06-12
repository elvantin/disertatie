# Architecture Quick Reference — SC MEDIA SRL

**Last Updated:** 2026-06-12

---

## VM Overview

| VM | OS | Role | Subnet | Public IP | Size |
|----|----|------|--------|-----------|------|
| vm-jmp-01 | Ubuntu 22.04 LTS | Jumphost — XFCE + xRDP + Ansible Control Node | mgmt | Yes (persistent) | Standard_B4ls_v2 |
| vm-web-01 | Ubuntu 22.04 LTS | nginx reverse proxy + SSL/TLS | prod | Yes (persistent) | Standard_B2s |
| vm-app-01 | Ubuntu 22.04 LTS | Application server (port 8080) | prod | No | Standard_B2s |
| vm-cms-01 | Ubuntu 22.04 LTS | WordPress + PHP-FPM + Postfix | prod | No | Standard_B2s |
| vm-db-01  | Windows Server 2022 | MySQL Community Server 8.0 | prod | No | Standard_B2s |
| vm-fs-01  | Windows Server 2022 | SMB File Server | prod | No | Standard_B2s |

IPs sunt alocate dinamic (DHCP Azure). Numai cele 2 IP-uri publice sunt statice (persistent RG).

---

## Network Layout

```
VNet: vnet-mediasrl-productie  (10.10.0.0/20)
├── snet-mgmt  10.10.12.0/24   vm-jmp-01
├── snet-prod  10.10.10.0/24   vm-web-01, vm-app-01, vm-cms-01, vm-db-01, vm-fs-01
└── snet-dev   10.10.11.0/24   (rezervat pentru mediu dev)
```

### Traffic Flow

```
Internet ──[HTTPS:443]──► vm-web-01 (nginx)
                              ├──[HTTP:80]──► vm-cms-01 (WordPress/PHP-FPM)
                              └──[HTTP:8080]──► vm-app-01 (API REST)

vm-cms-01 ──[MySQL:3306]──► vm-db-01 (MySQL 8.0)

Admin PC ──[RDP:3389]──► vm-jmp-01
vm-jmp-01 ──[SSH:22]──► vm-web-01, vm-app-01, vm-cms-01
vm-jmp-01 ──[WinRM:5985]──► vm-db-01, vm-fs-01
```

---

## Key Services per VM

### vm-jmp-01 (Jumphost)
- XFCE desktop + xRDP (port 3389)
- Ansible control node (azure.azcollection ≥ 3.15.0)
- Azure CLI — autentificare via Managed Identity (fără `az login`)
- Managed Identity: Reader pe persistent RG + Secrets User pe kv-mediasrl-persistent
- Workspace Ansible: `~/ansible`

### vm-web-01 (Web Server)
- nginx reverse proxy
- SSL/TLS (Let's Encrypt) — port 443
- DNS: `mediasrl.swedencentral.cloudapp.azure.com`

### vm-app-01 (Application Server)
- REST API (nginx port 8080)
- 6 endpoint-uri JSON: `/api/services`, `/api/clients`, `/api/projects`, `/api/team`, `/api/stats`, `/health`

### vm-cms-01 (CMS + Mail)
- WordPress + PHP-FPM (nginx frontend)
- Postfix SMTP relay
- Conexiune MySQL la vm-db-01 (port 3306)

### vm-db-01 (Database Server)
- MySQL Community Server 8.0 pe Windows Server 2022
- Baze de date: `wordpress_db`, `mediasrl_business`
- Port: 3306

### vm-fs-01 (File Server)
- Windows Server 2022
- SMB shares: Public, Marketing, IT, Backups
- LanmanServer service

---

## Ansible Inventory Groups

```
[jumphost]    vm-jmp-01
[webserver]   vm-web-01
[appserver]   vm-app-01
[cmsserver]   vm-cms-01
[database]    vm-db-01   (Windows, WinRM)
[fileserver]  vm-fs-01   (Windows, WinRM)

[linux:children]    webserver, appserver, cmsserver
[windows:children]  database, fileserver
```

Inventar dinamic Azure (`inventory/azure_rm.yml`) — autentificare via MSI (fără `az login`).

---

## Ansible Roles

| Rol | Target | Descriere |
|-----|--------|-----------|
| common | linux | Pachete de baza, NTP, SSH hardening, timezone |
| nginx | vm-web-01 | Reverse proxy, SSL/TLS, security headers |
| appserver | vm-app-01 | REST API pe nginx:8080 |
| wordpress | vm-cms-01 | WordPress + PHP-FPM + WP-CLI |
| postfix | vm-cms-01 | SMTP relay |
| mysql | vm-db-01 | MySQL 8.0 + baze de date + utilizatori |
| fileserver | vm-fs-01 | SMB shares, ACL-uri, SMBv1 dezactivat |
| hardening | toate | CIS Benchmarks Linux + Windows |

---

## Azure Resources

```
Subscription (7a0255bf-...)
│
├── rg-mediasrl-persistent/                  (supravietuieste teardown)
│   ├── pip-vm-jmp-01  (IP public static jumphost)
│   └── pip-vm-web-01  (IP public static webserver, DNS: mediasrl)
│
├── rg-mediasrl-packer-swedencentral/
│   └── gal_mediasrl  (Azure Compute Gallery)
│       ├── imgdef-ubuntu2204           (Ubuntu 22.04 base)
│       ├── imgdef-ubuntu2204-jumphost  (Ubuntu 22.04 + XFCE + Ansible)
│       └── imgdef-winserver2022        (Windows Server 2022 + WinRM)
│
├── rg-mediasrl-persistent/
│   └── kv-mediasrl-persistent  (Key Vault — secrete infrastructura)
│
└── rg-mediasrl-productie-swedencentral/
    ├── vnet-mediasrl-productie  (10.10.0.0/20)
    ├── kv-mediasrl-productie    (Key Vault — deployment secrets)
    ├── log-mediasrl-productie   (Log Analytics Workspace)
    ├── 6 x VMs + NICs + OS Disks
    └── Azure Policies (subscription scope)
```

---

## Secrets (Ansible Vault)

Stocate în `kv-mediasrl-persistent`, preluate automat de `ansible/scripts/create-ansible-vault.sh`:

| Secret KV | Variabila Vault |
|-----------|-----------------|
| `vm-admin-password` | `vault_admin_password` |
| `mysql-root-password` | `vault_mysql_root_password` |
| `mysql-wordpress-password` | `vault_mysql_wordpress_password` |
| `mysql-monitoring-password` | `vault_mysql_monitoring_password` |
| `mysql-api-password` | `vault_mysql_api_password` |
| `wordpress-admin-password` | `vault_wordpress_admin_password` |
| `ansible-vault-password` | (parola vault — salvata la `~/.vault-pass`) |

---

## WinRM Bootstrap (Automat)

Scriptul `bicep/scripts/windows-winrm-bootstrap.ps1` ruleaza automat pe Windows VMs
la deployment via `Microsoft.Compute/virtualMachines/runCommands`.
Nu este necesara nicio configurare manuala.
Log: `C:\Logs\mediasrl\winrm-bootstrap-*.log`

---

## Deployment Scripts (ordine de rulare)

```powershell
# 0. Bootstrap KV (o singura data)
.\scripts\0-bootstrap-keyvault.ps1

# 1. Build Packer images (o singura data sau la actualizare imagini)
.\scripts\1-build-packer-images.ps1

# 2. Deploy infrastructura
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod

# 3. Deploy Ansible pe jumphost
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod

# 4. Teste infrastructura
.\scripts\4-test-infrastructure.ps1

# Utilitar: afiseaza IP-uri + genereaza inventory static
.\scripts\get-vm-ips.ps1
```
