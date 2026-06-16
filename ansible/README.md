# Ansible Configuration Management — SC MEDIA SRL

Gestionarea configuratiei pentru 6 VMs Azure — proiect disertatie Master.

---

## Structura

```
ansible/
├── ansible.cfg                     # Configuratie Ansible (vault_password_file = ~/.vault-pass)
├── inventory/
│   ├── azure_rm.yml                # Inventar dinamic Azure (auth_source: msi) — PRIMAR
│   └── azure_rm_dev.yml            # Inventar dinamic — mediu dev
├── group_vars/
│   ├── all/
│   │   └── vault.yml               # Secrete encriptate AES-256 (gitignored, creat automat)
│   ├── linux.yml                   # Variabile comune Linux VMs
│   ├── windows.yml                 # Variabile WinRM Windows VMs
│   └── jumphost.yml                # Variabile specifice jumphost
├── playbooks/
│   ├── 1-setup-ssh-keys.yml        # Configureaza SSH keys intre VM-uri
│   └── 2-site.yml                  # Playbook principal — deploy complet
├── roles/
│   ├── common/                     # Baseline Linux (pachete, NTP, SSH hardening)
│   ├── nginx/                      # Reverse proxy + SSL/TLS (vm-web-01)
│   ├── appserver/                  # REST API pe nginx:8080 (vm-app-01)
│   ├── wordpress/                  # WordPress + PHP-FPM + WP-CLI (vm-cms-01)
│   ├── postfix/                    # SMTP relay (vm-cms-01)
│   ├── mysql/                      # MySQL Community 8.0 pe Windows (vm-db-01)
│   ├── fileserver/                 # SMB File Server pe Windows (vm-fs-01)
│   └── hardening/                  # CIS Benchmarks Linux + Windows
└── scripts/
    ├── create-ansible-vault.sh     # Preia secrete din KV via MSI + creeaza vault.yml
    └── demo-*.sh                   # Scripturi demo securitate
```

---

## Jumphost — Ansible Control Node

**vm-jmp-01** vine pre-configurat cu toate uneltele necesare prin imaginea Packer:
- OS: Ubuntu 22.04 LTS + XFCE Desktop + xRDP
- Ansible cu `azure.azcollection` (inventar dinamic Azure)
- `pywinrm` (conectivitate WinRM la Windows VMs)
- Azure CLI — autentificat via Managed Identity (fara `az login`)
- VS Code, Git, Remmina, utilitare DevOps

Workspace Ansible: `~/ansible` (copiat de `scripts/3-deploy-ansible-to-jumphost.ps1`).

---

## Inventar dinamic (azure_rm.yml)

Inventarul dinamic se autentifica via MSI (Managed Identity):

```bash
# Verifica inventarul
ansible-inventory -i inventory/azure_rm.yml --list
ansible-inventory -i inventory/azure_rm.yml --graph
```

Grupuri definite in `azure_rm.yml` prin tag-uri Azure:
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

---

## Ansible Vault — creare automata

`group_vars/all/vault.yml` se creeaza **automat** la rularea `scripts/3-deploy-ansible-to-jumphost.ps1`,
care apeleaza `ansible/scripts/create-ansible-vault.sh` pe jumphost via SSH.

Scriptul:
1. Se autentifica in Azure via Managed Identity (`az login --identity`)
2. Preia secretele din `kv-mediasrl-persistent`
3. Salveaza parola vault la `~/.vault-pass` (chmod 600)
4. Creeaza `group_vars/all/vault.yml` criptat AES-256

**Pentru recreare manuala (daca e necesar):**

```bash
cd ~/ansible
bash scripts/create-ansible-vault.sh
```

**Vizualizare/editare vault:**

```bash
ansible-vault view group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

Fisierul `ansible.cfg` contine `vault_password_file = ~/.vault-pass` — playbook-urile ruleaza fara `--ask-vault-pass`.

**Variabile stocate in vault:**

| Secret KV (kv-mediasrl-persistent) | Variabila Vault |
|------------------------------------|-----------------|
| `vm-admin-password` | `vault_admin_password` |
| `mysql-root-password` | `vault_mysql_root_password` |
| `mysql-wordpress-password` | `vault_mysql_wordpress_password` |
| `mysql-monitoring-password` | `vault_mysql_monitoring_password` |
| `mysql-api-password` | `vault_mysql_api_password` |
| `wordpress-admin-password` | `vault_wordpress_admin_password` |

---

## Utilizare

### Verificare conectivitate

```bash
cd ~/ansible

# Linux VMs (SSH)
ansible all -m ping

# Windows VMs (WinRM)
ansible windows -m win_ping
```

### Deploy complet

```bash
ansible-playbook playbooks/2-site.yml
```

### Deploy selectiv (tags)

```bash
ansible-playbook playbooks/2-site.yml --tags common
ansible-playbook playbooks/2-site.yml --tags nginx
ansible-playbook playbooks/2-site.yml --tags appserver
ansible-playbook playbooks/2-site.yml --tags cms
ansible-playbook playbooks/2-site.yml --tags database
ansible-playbook playbooks/2-site.yml --tags fileserver
ansible-playbook playbooks/2-site.yml --tags hardening
```

### Deploy pe VM-uri specifice

```bash
ansible-playbook playbooks/2-site.yml --limit webserver
ansible-playbook playbooks/2-site.yml --limit linux
ansible-playbook playbooks/2-site.yml --limit windows
ansible-playbook playbooks/2-site.yml --limit vm-cms-01
```

### Dry-run

```bash
ansible-playbook playbooks/2-site.yml --check
```

---

## Roluri Ansible

### common (Linux baseline)
- Update pachete (apt), utilitare (htop, vim, curl, etc.)
- Timezone Europe/Bucharest, NTP (systemd-timesyncd)
- SSH hardening, firewalld, baseline security

### nginx
- Reverse proxy pe vm-web-01
- SSL/TLS (Let's Encrypt), port 443
- Security headers (HSTS, CSP, X-Frame-Options)

### appserver
- REST API pe nginx:8080 (vm-app-01)
- 6 endpoint-uri JSON: `/api/services`, `/api/clients`, `/api/projects`, `/api/team`, `/api/stats`, `/health`

### wordpress
- PHP 8.1 + PHP-FPM, MySQL client
- WordPress + WP-CLI
- wp-config.php configurat din vault (conexiune MySQL la vm-db-01:3306)

### postfix
- SMTP relay pe vm-cms-01
- Mail aliases, SPF/DKIM

### mysql
- MySQL Community Server 8.0 pe Windows Server 2022 (vm-db-01)
- Baze de date: `wordpress_db`, `mediasrl_business`
- Utilizatori MySQL cu parole din vault
- Port: 3306

### fileserver
- SMB shares pe Windows Server 2022 (vm-fs-01): Public, Marketing, IT, Backups
- NTFS permissions, ACL-uri, dezactivare SMBv1
- LanmanServer service

### hardening
- CIS Benchmarks Linux + Windows
- Kernel hardening (sysctl), auditd, Windows Event Log
- Password policies, AppArmor (Ubuntu), Windows Defender

---

## Variabile grup

**`group_vars/all/`** — variabile globale + vault:

```yaml
timezone: "Europe/Bucharest"
ntp_servers:
  - "0.ro.pool.ntp.org"
  - "1.ro.pool.ntp.org"

company_name: "SC MEDIA SRL"
company_domain: "media-srl.ro"

db_host: "vm-db-01"
db_port: 3306
db_name: "wordpress_db"
```

**`group_vars/windows.yml`** — variabile WinRM (parola din vault):

```yaml
ansible_connection: winrm
ansible_winrm_transport: ntlm
ansible_winrm_server_cert_validation: ignore
ansible_port: 5985
ansible_user: azureadmin
ansible_password: "{{ vault_admin_password }}"
```

---

## Testare

```bash
# Ping toate VM-urile
ansible all -m ping

# Check disk
ansible all -m shell -a "df -h"

# Check serviciu MySQL pe Windows
ansible database -m win_service -a "name=MySQL80"

# Check serviciu SMB pe Windows
ansible fileserver -m win_service -a "name=LanmanServer"

# Check nginx
ansible webserver -m uri -a "url=http://localhost"
```

---

## Troubleshooting

### Debug general

```bash
ansible-playbook playbooks/2-site.yml -vvv
ansible-playbook playbooks/2-site.yml --syntax-check
ansible-playbook playbooks/2-site.yml --list-hosts
ansible-playbook playbooks/2-site.yml --list-tasks
ansible-playbook playbooks/2-site.yml --list-tags
```

### SSH connection failed (Linux VMs)

```bash
ssh azureadmin@<private-ip>
ansible linux -m ping -vvv
```

### WinRM connection failed (Windows VMs)

WinRM este configurat **automat** la deployment via `Microsoft.Compute/virtualMachines/runCommands`.
Log bootstrap: `C:\Logs\mediasrl\winrm-bootstrap-*.log`

```bash
ansible windows -m win_ping -vvv
```

Verificare pe VM (via RDP daca e necesar):
```powershell
Test-WSMan -ComputerName localhost
winrm get winrm/config
Get-Service WinRM
```

### Vault: re-creare

```bash
cd ~/ansible
bash scripts/create-ansible-vault.sh
```

### python3-winrm nu e instalat

Instalat in imaginea Packer. Daca lipseste:
```bash
sudo pip3 install pywinrm
```

---

## Documentatie

- [Ansible Documentation](https://docs.ansible.com/)
- [Ansible for Windows](https://docs.ansible.com/ansible/latest/user_guide/windows.html)
- [Azure Ansible Collection](https://docs.ansible.com/ansible/latest/collections/azure/azcollection/)
- [CIS Benchmarks Ubuntu 22.04](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [CIS Benchmarks Windows Server 2022](https://www.cisecurity.org/benchmark/microsoft_windows_server)

---

**Proiect:** Disertatie Master — Cloud Infrastructure Automation
**Autor:** SC IT SECURITY SRL
**Anul:** 2026
