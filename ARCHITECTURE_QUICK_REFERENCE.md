# Architecture Quick Reference - 6 VM Infrastructure

## VM Overview

| VM Name | OS | Role | IP Address | Public IP | Subnet |
|---------|-------|------|------------|-----------|--------|
| vm-jmp-01 | Rocky Linux 10 | Jumphost (GUI + xRDP + Ansible) | 10.10.12.x | Yes | mgmt |
| vm-fs-01 | Windows Server 2022 | File Server | 10.10.10.5 | No | prod |
| vm-db-01 | Windows Server 2022 | MS SQL Server 2022 | 10.10.10.10 | No | prod |
| vm-web-01 | Rocky Linux 10 | nginx Web Server | 10.10.10.15 | No | prod |
| vm-app-01 | Rocky Linux 10 | Application Server | 10.10.10.20 | No | prod |
| vm-cms-01 | Rocky Linux 10 | WordPress + Postfix | 10.10.10.25 | No | prod |

## Key Services by VM

### vm-jmp-01 (Jumphost)
- XRDP (Remote Desktop)
- Ansible Control Node
- Management tools
- SSH gateway to Linux VMs

### vm-fs-01 (File Server)
- Windows File Sharing (SMB)
- Shared network drives
- File storage

### vm-db-01 (Database Server) - NEW
- Microsoft SQL Server 2022 Developer Edition
- WordPress database (wordpress_db)
- Automated daily backups (2:00 AM)
- SQL Server Agent

### vm-web-01 (Web Server)
- nginx
- Reverse proxy
- SSL/TLS termination

### vm-app-01 (Application Server)
- Application runtime
- Business logic

### vm-cms-01 (CMS + Mail)
- WordPress (PHP-FPM + nginx)
- Postfix mail server
- Connects to vm-db-01 for database

## Network Connectivity

### Database Connections
```
vm-cms-01 (WordPress) --[TCP 1433]--> vm-db-01 (SQL Server)
```

### Web Traffic Flow
```
Internet --[HTTPS]--> vm-web-01 (nginx) --[HTTP]--> vm-cms-01 (WordPress/PHP-FPM)
```

### Management Access
```
Admin PC --[RDP]--> vm-jmp-01 --[SSH]--> Linux VMs
Admin PC --[RDP]--> vm-jmp-01 --[RDP]--> Windows VMs
```

## Firewall Rules Summary

### vm-db-01 (Database)
- **Inbound**: TCP 1433 (SQL Server) from 10.10.10.0/24
- **Inbound**: TCP 5986 (WinRM/HTTPS) from 10.10.12.0/24
- **Outbound**: All

### vm-cms-01 (WordPress)
- **Inbound**: TCP 80, 443 (HTTP/HTTPS) from vm-web-01
- **Inbound**: TCP 22 (SSH) from vm-jmp-01
- **Outbound**: TCP 1433 to vm-db-01
- **Outbound**: TCP 25 (SMTP) for mail

## Ansible Inventory Groups

```ini
[windows]
vm-fs-01
vm-db-01

[linux]
vm-web-01
vm-app-01
vm-cms-01

[database]
vm-db-01

[fileserver]
vm-fs-01

[webserver]
vm-web-01

[cms]
vm-cms-01

[jumphost]
vm-jmp-01
```

## Deployment Order

1. **Infrastructure (Bicep)**: Deploy all 6 VMs
2. **Jumphost**: Configure Ansible control node
3. **Windows Baseline**: Common Windows configuration
4. **Linux Baseline**: Common Linux configuration
5. **File Server**: Configure SMB shares
6. **Database Server**: Install SQL Server, create WordPress DB
7. **Web Server**: Configure nginx
8. **CMS Server**: Install WordPress with SQL Server drivers
9. **Hardening**: Apply CIS benchmarks to all VMs

## Critical Files

### Bicep
- `bicep/main.bicep` - Main orchestrator (6 VMs)
- `bicep/parameters/prod.bicepparam` - Production parameters

### Ansible
- `ansible/playbooks/site.yml` - Main playbook
- `ansible/inventory/hosts.ini` - Inventory (6 VMs)
- `ansible/roles/mssql/` - MS SQL Server role (NEW)
- `ansible/roles/wordpress/` - WordPress role (updated for SQL Server)

## Backup Strategy

### Database Backups (vm-db-01)
- **Frequency**: Daily at 2:00 AM
- **Location**: C:\SQLBackups
- **Retention**: 7 days
- **Type**: Full backup with compression
- **Managed by**: PowerShell script + Windows Task Scheduler

### File Server Backups (vm-fs-01)
- **Frequency**: Daily
- **Location**: Azure Backup vault
- **Retention**: 30 days

## Security Credentials

**Stored in Ansible Vault** (`ansible/group_vars/all/vault.yml`):
- Windows admin password
- SQL Server SA password
- WordPress database password
- SSH private keys

## Quick Commands

### Deploy Infrastructure
```bash
az deployment sub create \
  --location swedencentral \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/prod.bicepparam
```

### Configure All VMs
```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/site.yml
```

### Configure Database Server Only
```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/site.yml \
  --tags database
```

### Test Database Connection
```bash
# From vm-cms-01
sqlcmd -S vm-db-01 -U wordpress_user -P 'password' -Q "SELECT @@VERSION"
```

## Troubleshooting

### SQL Server Connection Issues
```bash
# Check SQL Server service status (on vm-db-01)
Get-Service MSSQLSERVER

# Check firewall rules
Get-NetFirewallRule -DisplayName "SQL Server*"

# Test connection from vm-cms-01
telnet vm-db-01 1433
```

### WordPress Database Errors
```bash
# Check PHP SQL Server drivers
php -m | grep sqlsrv

# Check SELinux booleans
getsebool httpd_can_network_connect_db

# Test database connection
php -r "phpinfo();" | grep -i sqlsrv
```

---

**Last Updated**: February 5, 2026
**Architecture Version**: 2.0 (6 VMs)
