# Infrastructure Update Summary: 5 VMs to 6 VMs

## Overview
The infrastructure has been successfully updated from 5 VMs to 6 VMs, with the following new architecture:

### VM Architecture (6 VMs Total)

1. **vm-jmp-01** (Rocky Linux) - Jumphost with GUI + xRDP + Ansible Control Node
2. **vm-fs-01** (Windows Server 2022) - File Server
3. **vm-db-01** (Windows Server 2022) - MS SQL Server 2022 Database Server **[NEW]**
4. **vm-web-01** (Rocky Linux) - nginx Web Server
5. **vm-app-01** (Rocky Linux) - Application Server
6. **vm-cms-01** (Rocky Linux) - WordPress CMS + Postfix Mail Server

### Key Architecture Changes

- **Database separation**: WordPress now connects to a remote MS SQL Server (vm-db-01) instead of local MySQL
- **Windows infrastructure**: 2 Windows Servers (vm-fs-01 for files, vm-db-01 for database)
- **Linux infrastructure**: 4 Rocky Linux servers (jumphost, web, app, cms)

## Files Modified

### 1. Bicep Infrastructure Files

#### `bicep/parameters/prod.bicepparam`
- Added vm-db-01 to the vms array
- Configuration: Windows Server 2022, Standard_B2s, prod subnet, no public IP

#### `bicep/main.bicep`
- Updated default vms array to include vm-db-01
- VM will be deployed with the same configuration as other Windows servers

### 2. Ansible Inventory

#### `ansible/inventory/hosts.ini`
- Added vm-db-01 to [windows] group (IP: 10.10.10.10)
- Created new [database] group containing vm-db-01
- Updated [production:children] to include database group
- Removed vm-cms-01 from [database] group (no longer hosting MySQL locally)

### 3. New MS SQL Role

Created complete Ansible role: `ansible/roles/mssql/`

#### `ansible/roles/mssql/defaults/main.yml`
- SQL Server 2022 Developer Edition configuration
- SA password and WordPress database credentials
- Backup settings (retention: 7 days, location: C:\SQLBackups)
- TCP port 1433, SQL Server Agent enabled

#### `ansible/roles/mssql/tasks/main.yml`
- Download and install SQL Server 2022
- Configure TCP/IP protocol and firewall (port 1433)
- Enable SQL Server and SQL Server Agent services
- Create WordPress database and user
- Deploy automated backup script
- Configure scheduled task for daily backups
- Clean up installation files

#### `ansible/roles/mssql/handlers/main.yml`
- Handler to restart SQL Server service
- Handler to restart SQL Server Agent

#### `ansible/roles/mssql/templates/backup-mssql.ps1.j2`
- PowerShell script for automated SQL Server backups
- Full backup of all user databases
- Automatic cleanup of old backups (7-day retention)
- Comprehensive logging

### 4. Updated WordPress Role

#### `ansible/roles/wordpress/defaults/main.yml`
- Changed db_host from "localhost" to "vm-db-01"
- Changed db_type to "sqlsrv" (SQL Server driver)
- Removed MySQL-specific variables

#### `ansible/roles/wordpress/tasks/main.yml`
- Removed local MySQL installation tasks
- Added Microsoft ODBC Driver 18 for SQL Server
- Added PHP SQL Server drivers (sqlsrv and pdo_sqlsrv)
- Added mssql-tools18 package
- Added SELinux boolean: httpd_can_network_connect_db (for remote DB access)
- Updated wp-config.php template reference for SQL Server connection

#### Deleted: `ansible/roles/wordpress/tasks/mysql-local.yml`
- No longer needed (using remote MS SQL instead of local MySQL)

### 5. Main Playbook

#### `ansible/playbooks/2-site.yml`
- Added new play: "Configure Database Server (Windows with MS SQL Server 2022)"
- Targets: hosts: database
- Applies role: mssql
- Tags: [database, mssql, windows]
- Runs before common baseline configuration

## Network Configuration

### IP Address Allocation (10.10.10.0/24 - Production Subnet)

- vm-fs-01: 10.10.10.5 (File Server)
- vm-db-01: 10.10.10.10 (Database Server) **[NEW]**
- vm-web-01: 10.10.10.15 (Web Server)
- vm-app-01: 10.10.10.20 (App Server)
- vm-cms-01: 10.10.10.25 (CMS + Mail)

### Firewall Rules

**vm-db-01 (Database Server)**:
- Port 1433 (SQL Server) - Inbound from production subnet
- WinRM 5986 (Ansible management) - Inbound from jumphost

**vm-cms-01 (WordPress Server)**:
- Port 1433 (SQL Server client) - Outbound to vm-db-01
- Ports 80/443 (HTTP/HTTPS) - Inbound from internet

## Security Considerations

1. **SQL Server Authentication**:
   - SA password stored in Ansible Vault
   - WordPress database user with minimal permissions (db_owner on wordpress_db only)

2. **Network Isolation**:
   - Database server on internal production subnet (no public IP)
   - Access only via jumphost or internal network

3. **Backup Strategy**:
   - Daily automated backups at 2:00 AM
   - 7-day retention policy
   - Backups stored on C:\SQLBackups

4. **SELinux Configuration**:
   - httpd_can_network_connect_db enabled on WordPress server
   - Allows PHP to connect to remote SQL Server

## Deployment Steps

### 1. Deploy Infrastructure (Bicep)
```bash
az deployment sub create \
  --location swedencentral \
  --template-file bicep/main.bicep \
  --parameters bicep/parameters/prod.bicepparam
```

### 2. Configure Database Server (Ansible)
```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/2-site.yml \
  --tags database
```

### 3. Configure WordPress Server (Ansible)
```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/2-site.yml \
  --tags cms
```

### 4. Run Full Deployment (All VMs)
```bash
ansible-playbook -i ansible/inventory/hosts.ini \
  ansible/playbooks/2-site.yml
```

## Testing Checklist

- [ ] vm-db-01 deploys successfully via Bicep
- [ ] SQL Server 2022 installs and starts
- [ ] WordPress database and user are created
- [ ] WordPress can connect to remote SQL Server from vm-cms-01
- [ ] Automated backups run successfully
- [ ] Firewall rules allow SQL Server traffic
- [ ] SELinux allows remote database connections
- [ ] WordPress site is accessible and functional

## Required Ansible Collections

Ensure the following collections are installed on the jumphost:

```bash
ansible-galaxy collection install community.windows
ansible-galaxy collection install ansible.windows
ansible-galaxy collection install community.general
ansible-galaxy collection install ansible.posix
```

## Database Connection Details

**Connection String (from WordPress)**:
- Host: vm-db-01
- Port: 1433
- Database: wordpress_db
- User: wordpress_user
- Driver: sqlsrv (Microsoft SQL Server Native Client)

## Cost Implications

- **New VM**: vm-db-01 (Standard_B2s) - ~€30/month
- **Total Infrastructure**: 6 VMs x €30/month = ~€180/month
- **Storage**: Additional 128GB SSD for database = ~€10/month

**Total estimated monthly cost**: ~€190/month

## Documentation Updates Needed

1. Update architecture diagrams to show 6 VMs
2. Update network topology to include vm-db-01
3. Update deployment documentation with new database configuration
4. Update security documentation with SQL Server hardening
5. Update backup and recovery procedures

## Migration Notes

**If migrating from existing 5-VM setup**:

1. Export existing WordPress database from MySQL
2. Deploy new vm-db-01
3. Convert MySQL dump to SQL Server format (using tools like MySQL to MSSQL converter)
4. Import data into SQL Server
5. Update WordPress configuration
6. Test thoroughly before decommissioning old MySQL setup

---

**Date**: February 5, 2026
**Updated by**: Claude Sonnet 4.5
**Status**: Ready for deployment
