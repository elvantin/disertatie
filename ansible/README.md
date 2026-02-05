# Ansible Configuration Management - SC MEDIA SRL

Infrastructure automation pentru proiect disertație master - Managementul configurației pentru 5 VMs în Azure.

## 📋 Structura

```
ansible/
├── ansible.cfg              # Configurație Ansible
├── inventory/
│   ├── hosts.ini           # Inventory static
│   └── azure_rm.yml        # Dynamic inventory pentru Azure
├── playbooks/
│   ├── site.yml            # Playbook principal (orchestrare completă)
│   ├── deploy-services.yml # Deploy doar servicii
│   └── harden-all.yml      # Hardening security
└── roles/
    ├── common/             # Configurație baseline (toate VM-urile)
    ├── nginx/              # Web server (vm-web-01)
    ├── mysql/              # Database (vm-db-01, Windows)
    ├── wordpress/          # CMS (vm-cms-01)
    ├── postfix/            # Mail server (vm-cms-01)
    └── hardening/          # CIS Benchmark hardening
```

## 🚀 Utilizare

### 1. Pregătire Ansible Control Node

```bash
# Instalare Ansible (Linux/WSL2)
sudo apt update && sudo apt install -y ansible python3-pip

# Instalare Azure collection pentru dynamic inventory
ansible-galaxy collection install azure.azcollection
pip3 install azure-cli azure-identity
```

### 2. Configurare Inventory

Editați `inventory/hosts.ini` și completați:
- IP-ul public al Jumphost (vm-jmp-01)
- Parole/chei SSH

### 3. Deployment Complet

```bash
# Deployment complet (baseline + servicii + hardening)
ansible-playbook playbooks/site.yml

# Deployment doar servicii
ansible-playbook playbooks/deploy-services.yml

# Doar hardening security
ansible-playbook playbooks/harden-all.yml

# Deployment cu tags specifice
ansible-playbook playbooks/site.yml --tags "nginx,mysql"

# Dry-run (test fără modificări)
ansible-playbook playbooks/site.yml --check
```

### 4. Deployment Selectiv

```bash
# Doar Web Server
ansible-playbook playbooks/site.yml --limit webserver

# Doar Linux VMs
ansible-playbook playbooks/site.yml --limit linux

# Doar Windows VMs
ansible-playbook playbooks/site.yml --limit windows
```

## 🔐 Securitate - Ansible Vault

Secretele (parole MySQL, WordPress keys) trebuie stocate în Ansible Vault:

```bash
# Creare vault pentru secrete
ansible-vault create group_vars/all/vault.yml

# Editare vault
ansible-vault edit group_vars/all/vault.yml

# Deployment cu vault
ansible-playbook playbooks/site.yml --ask-vault-pass
```

## 📦 Roluri Ansible

### common
- Update pachete, instalare utilities
- Configurare timezone (Europe/Bucharest)
- NTP/time sync
- SSH hardening (Linux)
- Baseline security

### nginx
- Instalare nginx
- Virtual host pentru SC MEDIA SRL
- Reverse proxy către vm-app-01
- Hardening HTTP headers

### mysql
- Instalare MySQL 8.0 (Windows Server)
- Configurare my.ini
- Database + user pentru WordPress
- Backup automat (script PowerShell + Scheduled Task)

### wordpress
- Instalare PHP 8.x + PHP-FPM
- Deployment WordPress
- Configurare wp-config.php
- Nginx + PHP-FPM integration

### postfix
- Instalare Postfix
- Configurare SMTP relay
- Mail aliases

### hardening
- CIS Benchmark compliance
- Kernel hardening (sysctl)
- Audit logging (auditd Linux, Event Log Windows)
- Password policies
- File permissions
- Disable unnecessary services

## 🧪 Testare

```bash
# Ping test
ansible all -m ping

# Check disk space
ansible all -a "df -h"

# Gather facts
ansible all -m setup

# Test conectivitate la servicii
ansible webserver -m uri -a "url=http://localhost"
```

## 📝 Configurare Variabile

Variabilele pot fi suprascrise în:
- `group_vars/all.yml` - variabile globale
- `group_vars/linux.yml` - specific Linux
- `group_vars/windows.yml` - specific Windows
- `host_vars/vm-web-01.yml` - specific unui host

## 🔄 Troubleshooting

```bash
# Verbose mode (debug)
ansible-playbook playbooks/site.yml -vvv

# Check syntax
ansible-playbook playbooks/site.yml --syntax-check

# List hosts
ansible-playbook playbooks/site.yml --list-hosts

# List tasks
ansible-playbook playbooks/site.yml --list-tasks
```

## 📚 Documentație

- [Ansible Documentation](https://docs.ansible.com/)
- [Azure Ansible Collection](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)

---

**Proiect:** Disertație Master - Cloud Infrastructure Automation
**Autor:** SC IT SECURITY SRL
**Anul:** 2026
