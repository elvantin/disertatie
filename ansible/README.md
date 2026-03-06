# Ansible Configuration Management - SC MEDIA SRL

Infrastructure automation pentru proiect disertație master - Managementul configurației pentru 6 VMs în Azure.

## 📋 Structura

```
ansible/
├── ansible.cfg              # Configurație Ansible
├── inventory/
│   ├── hosts.ini           # Inventory static
│   └── azure_rm.yml        # Dynamic inventory pentru Azure
├── playbooks/
│   ├── site.yml            # Playbook principal (orchestrare completă)
│   ├── setup-ssh-keys.yml  # Configurare SSH keys între VMs
│   ├── deploy-services.yml # Deploy doar servicii
│   └── harden-all.yml      # Hardening security
└── roles/
    ├── common/             # Configurație baseline (toate VM-urile Linux)
    ├── nginx/              # Web server (vm-web-01)
    ├── wordpress/          # CMS (vm-cms-01)
    ├── postfix/            # Mail server (vm-cms-01)
    ├── sqlserver/          # SQL Server (vm-db-01, Windows)
    ├── fileserver/         # File Server (vm-fs-01, Windows)
    └── hardening/          # CIS Benchmark hardening
```

## 🚀 Utilizare

### 1. Pregătire Ansible Control Node (Jumphost)

**Jumphost (vm-jmp-01)** vine pre-configurat cu Ansible prin bootstrap script:
- OS: Ubuntu 22.04 LTS + XFCE Desktop
- Ansible + python3-winrm (pentru Windows VMs)
- Azure CLI
- VS Code, Git, și alte DevOps tools

```bash
# Verificare instalare Ansible
ansible --version

# Instalare Azure collection pentru dynamic inventory (dacă e necesar)
ansible-galaxy collection install azure.azcollection
```

### 2. Configurare Inventory

Editați `inventory/hosts.ini` și completați:
- IP-uri private ale tuturor VMs
- Credențiale SSH pentru Linux VMs
- Credențiale WinRM pentru Windows VMs

**Exemplu inventory:**

```ini
[webserver]
vm-web-01 ansible_host=10.10.10.4 ansible_user=azureadmin

[appserver]
vm-app-01 ansible_host=10.10.10.5 ansible_user=azureadmin

[cmsserver]
vm-cms-01 ansible_host=10.10.10.6 ansible_user=azureadmin

[database]
vm-db-01 ansible_host=10.10.10.7 ansible_user=azureadmin ansible_connection=winrm ansible_winrm_server_cert_validation=ignore

[fileserver]
vm-fs-01 ansible_host=10.10.10.8 ansible_user=azureadmin ansible_connection=winrm ansible_winrm_server_cert_validation=ignore

[linux:children]
webserver
appserver
cmsserver

[windows:children]
database
fileserver
```

### 3. Setup SSH Keys (First Step)

**IMPORTANT:** Primul pas după bootstrap este configurarea SSH keys între jumphost și Linux VMs:

```bash
cd ~/ansible-workspace

# Generate SSH key pair pe jumphost (dacă nu există)
ssh-keygen -t rsa -b 4096 -C "jumphost-ansible" -f ~/.ssh/id_rsa -N ""

# Deploy SSH keys to Linux VMs (folosește password authentication pentru prima dată)
ansible-playbook playbooks/1-setup-ssh-keys.yml --ask-pass

# Test connectivity
ansible all -m ping
```

### 4. Deployment Complet

```bash
# Deployment complet (baseline + servicii + hardening)
ansible-playbook playbooks/2-site.yml

# Deployment doar servicii
ansible-playbook playbooks/obsolete/deploy-services.yml

# Doar hardening security
ansible-playbook playbooks/obsolete/harden-all.yml

# Deployment cu tags specifice
ansible-playbook playbooks/2-site.yml --tags "nginx,wordpress"

# Dry-run (test fără modificări)
ansible-playbook playbooks/2-site.yml --check
```

### 5. Deployment Selectiv

```bash
# Doar Web Server
ansible-playbook playbooks/2-site.yml --limit webserver

# Doar Linux VMs
ansible-playbook playbooks/2-site.yml --limit linux

# Doar Windows VMs
ansible-playbook playbooks/2-site.yml --limit windows

# Doar un VM specific
ansible-playbook playbooks/2-site.yml --limit vm-cms-01
```

## 🔐 Securitate - Ansible Vault

Secretele (parole SQL Server, WordPress keys, certificates) trebuie stocate în Ansible Vault:

```bash
# Creare vault pentru secrete
ansible-vault create group_vars/all/vault.yml

# Editare vault
ansible-vault edit group_vars/all/vault.yml

# Deployment cu vault
ansible-playbook playbooks/2-site.yml --ask-vault-pass

# Sau folosiți un password file
echo 'your-vault-password' > ~/.vault_pass
chmod 600 ~/.vault_pass
ansible-playbook playbooks/2-site.yml --vault-password-file ~/.vault_pass
```

## 📦 Roluri Ansible

### common (Linux baseline)
- Update pachete (apt)
- Instalare utilities (htop, vim, curl, etc.)
- Configurare timezone (Europe/Bucharest)
- NTP/time sync (systemd-timesyncd)
- SSH hardening
- Firewall configuration (firewalld)
- Baseline security

### nginx
- Instalare nginx pe Ubuntu
- Virtual host pentru SC MEDIA SRL
- Reverse proxy către vm-app-01
- SSL/TLS configuration
- Hardening HTTP headers (HSTS, CSP, X-Frame-Options)
- Log rotation

### wordpress
- Instalare PHP 8.1 + PHP-FPM
- MySQL/MariaDB client pentru conexiune la vm-db-01
- Deployment WordPress
- Configurare wp-config.php (database connection)
- Nginx + PHP-FPM integration
- WP-CLI installation

### postfix
- Instalare Postfix pe Ubuntu
- Configurare SMTP relay
- Mail aliases
- SPF/DKIM configuration

### sqlserver
- Instalare SQL Server 2022 pe Windows Server via DSC
- Configurare SQL Server Management Studio
- Database creation pentru WordPress
- User creation și permissions
- Backup configuration (automated via SQL Agent)
- Firewall rules pentru port 1433

### fileserver
- Configurare SMB shares pe Windows Server
- NTFS permissions
- Access Control Lists (ACLs)
- Quota management
- Disable SMBv1 pentru securitate
- Audit logging

### hardening
- CIS Benchmark compliance pentru Ubuntu și Windows Server
- Kernel hardening (sysctl pentru Linux)
- Audit logging (auditd Linux, Windows Event Log)
- Password policies
- File permissions
- Disable unnecessary services
- AppArmor configuration (Ubuntu)
- Windows Defender configuration

## 🧪 Testare

```bash
# Ping test (toate VMs)
ansible all -m ping

# Check disk space
ansible all -m shell -a "df -h"

# Gather facts despre toate VMs
ansible all -m setup

# Test conectivitate la servicii
ansible webserver -m uri -a "url=http://localhost"

# Check running services
ansible linux -m service -a "name=nginx state=started"

# Windows-specific commands
ansible windows -m win_service -a "name=MSSQLSERVER"
```

## 📝 Configurare Variabile

Variabilele pot fi suprascrise în:
- `group_vars/all.yml` - variabile globale
- `group_vars/linux.yml` - specific Ubuntu VMs
- `group_vars/windows.yml` - specific Windows Server VMs
- `host_vars/vm-web-01.yml` - specific unui host
- `group_vars/all/vault.yml` - secrete (encrypted)

**Exemplu group_vars/all.yml:**

```yaml
---
# Global variables
timezone: "Europe/Bucharest"
ntp_servers:
  - "0.ro.pool.ntp.org"
  - "1.ro.pool.ntp.org"

# Database connection
db_host: "vm-db-01"
db_port: 1433
db_name: "wordpress_db"
db_user: "wp_user"
# db_password stored in vault.yml

# Company information
company_name: "SC MEDIA SRL"
company_domain: "media-srl.ro"
```

## 🔄 Troubleshooting

```bash
# Verbose mode (debug)
ansible-playbook playbooks/2-site.yml -vvv

# Check syntax
ansible-playbook playbooks/2-site.yml --syntax-check

# List hosts
ansible-playbook playbooks/2-site.yml --list-hosts

# List tasks
ansible-playbook playbooks/2-site.yml --list-tasks

# List tags
ansible-playbook playbooks/2-site.yml --list-tags

# Test WinRM connectivity to Windows VMs
ansible windows -m win_ping

# Check Python interpreter on Linux VMs
ansible linux -m setup -a "filter=ansible_python_version"
```

## 🐛 Common Issues

### SSH Connection Failed (Linux VMs)

```bash
# Test manual SSH connection
ssh azureadmin@vm-web-01

# Check if SSH key was deployed
ansible linux -m shell -a "cat ~/.ssh/authorized_keys" --ask-pass

# Re-deploy SSH keys
ansible-playbook playbooks/1-setup-ssh-keys.yml --ask-pass --limit vm-web-01
```

### WinRM Connection Failed (Windows VMs)

```bash
# Enable WinRM on Windows VMs manually via RDP first
Enable-PSRemoting -Force
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any

# Test from jumphost
ansible windows -m win_ping -vvv
```

## 📚 Documentație

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible for Windows](https://docs.ansible.com/ansible/latest/user_guide/windows.html)
- [Azure Ansible Collection](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/)
- [CIS Benchmarks - Ubuntu 22.04](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [CIS Benchmarks - Windows Server 2022](https://www.cisecurity.org/benchmark/microsoft_windows_server)

---

**Proiect:** Disertație Master - Cloud Infrastructure Automation
**Autor:** SC IT SECURITY SRL
**Anul:** 2026
