# Architecture Quick Reference — SC MEDIA SRL

**Last Updated:** 2026-06-16

---

## VM Overview

| VM | OS (Packer Image) | Role | Subnet | Public IP | Size |
|----|--------------------|------|--------|-----------|------|
| vm-jmp-01 | Ubuntu 22.04 `imgdef-ubuntu2204-jumphost` | Jumphost — XFCE + xRDP + Ansible Control Node | snet-mgmt | Yes (persistent) | Standard_B4ls_v2 |
| vm-web-01 | Ubuntu 22.04 `imgdef-ubuntu2204` | nginx reverse proxy + SSL/TLS + WAF | snet-prod | Yes (persistent) | Standard_B2s |
| vm-app-01 | Ubuntu 22.04 `imgdef-ubuntu2204` | Application server — REST API (port 8080) | snet-prod | No | Standard_B2s |
| vm-cms-01 | Ubuntu 22.04 `imgdef-ubuntu2204` | WordPress + PHP-FPM + Postfix | snet-prod | No | Standard_B2s |
| vm-db-01  | Windows Server 2022 `imgdef-winserver2022` | MySQL Community Server 8.0 + TDE | snet-prod | No | Standard_B2s |
| vm-fs-01  | Windows Server 2022 `imgdef-winserver2022` | SMB File Server (Storage Pool D:\\) | snet-prod | No | Standard_B2s |

IP-urile private sunt alocate dinamic (DHCP Azure). Cele 2 IP-uri publice sunt statice (`rg-mediasrl-persistent`).

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
Internet ──[HTTPS:443]──► vm-web-01 (nginx + ModSecurity WAF)
                              ├──[HTTP:80]──► vm-cms-01 (WordPress/PHP-FPM)
                              └──[HTTP:8080]──► vm-app-01 (API REST)

vm-cms-01 ──[MySQL:3306]──► vm-db-01 (MySQL 8.0 + TDE)
vm-db-01  ──[MySQL:3306]──► accessible din 10.10.12.% (jumphost subnet)

Admin PC ──[RDP:3389]──► vm-jmp-01 (xRDP)
Admin PC ──[SSH:22]────► vm-jmp-01

vm-jmp-01 ──[SSH:22]────► vm-web-01, vm-app-01, vm-cms-01
vm-jmp-01 ──[WinRM:5985]► vm-db-01, vm-fs-01  (transport: basic)
vm-jmp-01 ──[RDP:3389]──► vm-db-01, vm-fs-01  (via Remmina)
```

---

## NSG Rules Summary

| NSG | Permite inbound | Blochează |
|-----|-----------------|-----------|
| **nsg-mgmt** | RDP:3389 + SSH:22 din IP_admin | Tot restul |
| **nsg-prod** | HTTPS:443 (Internet→web-01), HTTP:80 (VNet→web-01), SSH:22 + RDP:3389 + WinRM:5985 (mgmt→prod), MySQL:3306 + SMTP:25/587 + SMB:445 (prod→prod) | Tot restul |
| **nsg-dev** | SSH:22 + RDP:3389 (mgmt→dev) | Tot restul |

> `IP_admin` = detectat automat la deploy de `2-deploy-teardown-bicep.ps1`.

---

## Key Services per VM

### vm-jmp-01 (Jumphost)
- **Desktop:** XFCE4 + xRDP (port 3389), Firefox ESR, Remmina (profil RDP pre-configurat pentru vm-db-01, vm-fs-01)
- **Ansible:** control node cu `azure.azcollection`, `pywinrm` pentru Windows VMs
- **Azure CLI:** autentificare via Managed Identity — fără `az login`
- **Managed Identity:** Reader pe `rg-mediasrl-persistent`, Key Vault Secrets User pe `kv-mediasrl-persistent`
- **Workspace Ansible:** `~/ansible`
- **Demo scripts:** `~/ansible/scripts/demo-*.sh`
- **Post-boot finalizare:** `scripts/finalize-jumphost.sh` rulat via Azure Custom Script Extension la primul boot

### vm-web-01 (Web Server)
- **nginx:** reverse proxy, HTTP/2, gzip, server_tokens off
- **SSL/TLS:** Let's Encrypt (certbot via `scripts/certbot-letsencrypt.sh`), TLS 1.2/1.3 only, ECDHE/DHE ciphers, DH 4096-bit
- **HSTS:** max-age 31536000 (1 an), OCSP stapling
- **Security headers:** X-Frame-Options DENY, X-Content-Type-Options, Referrer-Policy, CSP, Permissions-Policy
- **ModSecurity WAF:** OWASP CRS 3.2.1, mod: On (block+log), paranoia level 1, audit log JSON la `/var/log/nginx/modsec_audit.log`; WordPress exclusions active
- **Rate limiting:** activat de `harden-security(daca_nu_rulez_demouri).yml` sau demo-1 (5 req/min pe /wp-login.php, /wp-admin/, /xmlrpc.php, /api/)
- **fail2ban:** jails SSH + nginx-http-auth + nginx-req-limit + nginx-botsearch; ban 1h / 5 încercări; ignoreip 10.10.12.0/24
- **DNS:** `mediasrl.swedencentral.cloudapp.azure.com`

### vm-app-01 (Application Server)
- REST API pe nginx:8080
- 6 endpoint-uri JSON: `/api/services`, `/api/clients`, `/api/projects`, `/api/team`, `/api/stats`, `/health`
- Date business statice SC MEDIA SRL (fișiere JSON servite de nginx)
- Acces restrictionat: doar din VNet (nu expus direct la Internet); accesat de vm-web-01 via proxy_pass
- `index.html` pe vm-web-01 afișează date live din `/api/stats` via fetch JavaScript

### vm-cms-01 (CMS + Mail)
- **WordPress** + PHP 8.1 + PHP-FPM (nginx local frontend pe port 80)
- **WP-CLI** pentru management WordPress din linia de comandă
- **Postfix** SMTP relay
- Conexiune MySQL la vm-db-01 (port 3306, user `wp_user`, parolă din Ansible Vault)
- fail2ban activ (SSH)

### vm-db-01 (Database Server)
- **MySQL Community Server 8.0.45** pe Windows Server 2022 (serviciu `MySQL80`)
- **Baze de date:** `wordpress_db`, `mediasrl_business` (5 tabele: angajați, servicii, clienți, proiecte, facturi)
- **Utilizatori MySQL:**
  - `root` — admin (acces local + din jumphost 10.10.12.%)
  - `wp_user` — WordPress (`wordpress_db`)
  - `api_user` — REST API (`mediasrl_business`)
  - `monitoring` — monitoring read-only
- **TDE (Transparent Data Encryption):** keyring file plugin, date criptate la rest
- **Port:** 3306 | **Bind:** 0.0.0.0 (filtrat de NSG)
- **WinRM:** configurat automat la deployment via `runCommands`; transport Ansible: `basic` (nu ntlm — MD4 dezactivat pe OpenSSL 3.x)
- **Backup local:** `C:\MySQL\Backups` (retenție 7 zile)

### vm-fs-01 (File Server)
- **Windows Server 2022**, serviciu `LanmanServer`
- **Storage Pool** `MediaSRL-FileData` pe D:\ (disk SCSI LUN 0 dedicat, init via `init-storage-pool.ps1`)
- **SMB Shares:** Public, Marketing, IT, Backups (ACL-uri NTFS per departament)
- **SMBv1 dezactivat** (securitate)
- **WinRM:** configurat automat la deployment via `runCommands`; transport Ansible: `basic`

---

## Ansible Roles (13 roluri)

| Rol | Target | Descriere |
|-----|--------|-----------|
| `common` | linux | Update apt, pachete comune, NTP, timezone, SSH de baza, firewalld |
| `nginx` | vm-web-01 | Reverse proxy, SSL/TLS, HTTP/2, security headers, index.html cu live API fetch |
| `appserver` | vm-app-01 | REST API pe nginx:8080, 6 endpoint-uri JSON, date business statice |
| `wordpress` | vm-cms-01 | WordPress + PHP 8.1-FPM + WP-CLI, wp-config din vault |
| `postfix` | vm-cms-01 | SMTP relay, mail aliases, SPF/DKIM |
| `mysql` | vm-db-01 | MySQL 8.0.45 pe Windows: instalare MSI, DB-uri, utilizatori, TDE, hardening, backup local |
| `fileserver` | vm-fs-01 | Storage Pool D:\\, SMB shares, NTFS ACL-uri, dezactivare SMBv1, audit |
| `hardening` | toate | CIS Benchmarks: kernel sysctl, auditd, servicii dezactivate, politici parole |
| `fail2ban` | linux | Jails: SSH + nginx-http-auth + nginx-req-limit + botsearch; ban 1h / 5 fail; ignoreip mgmt subnet |
| `ssh-hardening` | linux | KexAlgorithms curve25519, Ciphers AEAD, MACs ETM; AllowUsers azureadmin; banner |
| `modsecurity` | vm-web-01 | ModSecurity 3 + OWASP CRS 3.2.1, mod On, audit JSON, WordPress exclusions |
| `monitoring` | toate | Health scripts (cron/Task Scheduler la 5 min), metrici servicii/porturi per VM |
| `jumphost` | vm-jmp-01 | Configurare Ansible workspace, Remmina profiles, MOTD, demo scripts |

---

## Ansible Playbooks (ordine rulare)

| Playbook | Scop |
|----------|------|
| `1-setup-ssh-keys.yml` | Generare + distribuire chei SSH pe Linux VMs |
| `2-site.yml` | Deploy complet (toate rolurile de baza) |
| `3-verify.yml` | Verificare servicii pe toate VM-urile (teste functionale) |
| `4-harden-nginx-ssl_ssllabs.com_ssltest.yml` | Hardening SSL/TLS nginx: DH 4096-bit, TLS 1.2/1.3, HSTS, OCSP stapling, security headers (A+ SSL Labs) |
| `harden-security(daca_nu_rulez_demouri).yml` | Hardening avansat: fail2ban, WAF, ssh-hardening, MySQL TDE — alternativă la demo-uri |
| `6-monitoring.yml` | Health check scripts + cron/Scheduled Tasks pe toate VM-urile |
| `bootstrap-windows-winrm.yml` | Activare WinRM manual (fallback — in mod normal runCommands face asta automat) |

**Script wrapper:** `~/ansible/run-playbook.sh` — genereaza automat `.log` + `.clean.log` + `.html` per executie.

**Script certbot:** `~/ansible/scripts/certbot-letsencrypt.sh` — obtine certificat Let's Encrypt, gestioneaza NSG temporar (port 80 deschis pentru challenge HTTP-01, inchis imediat dupa).

---

## Demo Scripts (securitate)

Scripturi interactive care demonstreaza masurile de securitate in actiune:

| Script | Ce demonstreaza |
|--------|-----------------|
| `demo-1-rate-limiting.sh` | Rate limiting nginx: 429 Too Many Requests la depasirea limitei |
| `demo-2-fail2ban.sh` | Blocare IP dupa 5 tentative SSH esuate; ignoreip arata ca mgmt subnet (10.10.12.0/24) nu poate fi banat |
| `demo-3-ssh-hardening.sh` | Respingere algoritmi SSH slabi (MD5, arcfour, diffie-hellman-group1) |
| `demo-4-modsecurity.sh` | Blocari WAF: SQL injection, XSS, LFI (path traversal), RCE |
| `demo-5-mysql-hardening.sh` | Acces refuzat MySQL din exterior, TDE (fisiere .ibd criptate), audit log |
| `demo-all-hardenings.sh` | Rulare secventiala a tuturor demo-urilor de mai sus |

Rulare din jumphost: `cd ~/ansible && bash scripts/demo-all-hardenings.sh`

> **Ordine obligatorie:** demo-urile trebuie rulate ÎNAINTE de `harden-security(daca_nu_rulez_demouri).yml` — deployeaza hardeningurile progresiv pentru contrast BEFORE/AFTER.

---

## Security Features Summary

```
Nivel                 Masura                          Implementata de
─────────────────────────────────────────────────────────────────────
Retea                 NSG: whitelist IP admin         Bicep (nsg.bicep)
                      Segmentare mgmt/prod/dev        Bicep (networking.bicep)
                      WinRM restrictionat la mgmt     NSG nsg-prod regula 115

Imagini               Hardening de baza la build      Packer
                      WinRM pre-configurat             Packer (configure-winrm.ps1)
                      Timezone corecta (RO)           Packer (toate 3 imaginile)

IaC / Deployment      Secrets in Key Vault            Bicep (keyvault.bicep)
                      MSI fara credentiale            Bicep (role-assignment.bicep)
                      KV access policy MSI            Bicep (kv-access-policy.bicep)
                      WinRM bootstrap automat         Bicep (runCommands)

Ansible               CIS Benchmarks                  Rol hardening
                      SSH: algoritmi moderni, banner  Rol ssh-hardening
                      Brute-force SSH/nginx           Rol fail2ban (ignoreip mgmt)
                      WAF (OWASP CRS 3.2.1)           Rol modsecurity
                      MySQL TDE + hardening           Rol mysql + playbook harden
                      SSL/TLS A+ grade                Playbook 4-harden-nginx-ssl
                      HSTS, OCSP, security headers    Playbook 4-harden-nginx-ssl
                      Rate limiting nginx             Rol nginx + playbook harden
                      SMBv1 dezactivat               Rol fileserver

Secrete               Azure Key Vault (infra)         0-bootstrap-keyvault.ps1
                      Ansible Vault AES-256           create-ansible-vault.sh
                      Parola vault -> ~/.vault-pass   create-ansible-vault.sh
                      Nicio parola hardcodata          Principiu de design

Monitoring            Azure Monitor Agent             Rol monitoring + ama.bicep
                      Health scripts per VM           Rol monitoring (inline config)
                      Alerte CPU/disk/mem             monitoring.bicep
                      Audit log Linux (auditd)        Rol hardening
                      Windows Event Log               Rol hardening
                      ModSecurity audit JSON          Rol modsecurity
```

---

## Monitoring

| Componenta | Resursa | Detalii |
|-----------|---------|---------|
| Azure Monitor Agent | AMA pe toate 6 VM-urile | Instalat via `ama.bicep` + configurat de rolul `monitoring` |
| Log Analytics | `log-mediasrl-productie` | Ingesta 5GB/luna free; retentie 31 zile |
| Health check Linux | `/usr/local/bin/check-health.sh` | Cron la 5 minute; scrie in syslog (tag: `mediasrl-health`) |
| Health check Windows | `C:\Scripts\check-health.ps1` | Task Scheduler la 5 minute; scrie in Application Event Log (`mediasrl-health`) |
| Alerte | Action Group (email) | CPU ≥ 90%, Disk ≥ 90%, Memory ≥ 90% |
| Config per VM | inline in `playbooks/6-monitoring.yml` | `set_fact` cu `_vm_map` — fara dependenta de `host_vars` |

**Servicii monitorizate per VM:**

| VM | Servicii | Porturi |
|----|---------|---------|
| vm-jmp-01 | sshd, xrdp | 22, 3389 |
| vm-web-01 | nginx | 80, 443 |
| vm-app-01 | nginx | 8080 |
| vm-cms-01 | nginx, php8.1-fpm, postfix | 80, 25 |
| vm-db-01 | MySQL80 | 3306 |
| vm-fs-01 | LanmanServer | 445 |

---

## Azure Resources

```
Subscription (7a0255bf-...)
│
├── rg-mediasrl-persistent/                     (supravietuieste teardown)
│   ├── pip-vm-jmp-01  (IP public static jumphost)
│   ├── pip-vm-web-01  (IP public static webserver — DNS: mediasrl)
│   └── kv-mediasrl-persistent  (Key Vault — secrete infrastructura)
│
├── rg-mediasrl-packer-swedencentral/
│   └── gal_mediasrl  (Azure Compute Gallery)
│       ├── imgdef-ubuntu2204            (Ubuntu 22.04 LTS base hardened + timezone RO)
│       ├── imgdef-ubuntu2204-jumphost   (Ubuntu 22.04 + XFCE + Ansible + tools + timezone RO)
│       └── imgdef-winserver2022         (Windows Server 2022 + WinRM + timezone E. Europe Std Time)
│
└── rg-mediasrl-productie-swedencentral/
    ├── vnet-mediasrl-productie  (10.10.0.0/20)
    │   ├── snet-mgmt + nsg-mgmt
    │   ├── snet-prod + nsg-prod
    │   └── snet-dev  + nsg-dev
    ├── kv-mediasrl-productie    (Key Vault — deployment parameters)
    ├── log-mediasrl-productie   (Log Analytics Workspace)
    ├── 6 x VMs + NICs + OS Disks
    ├── 6 x Azure Monitor Agent extensions
    └── Azure Policies (subscription scope — tagging, locatie, SKU-uri)
```

---

## Secrets (Ansible Vault)

Stocate in `kv-mediasrl-persistent`, preluate automat de `ansible/scripts/create-ansible-vault.sh` via MSI:

| Secret KV | Variabila Vault | Folosita de |
|-----------|-----------------|-------------|
| `vm-admin-password` | `vault_admin_password` | SSH/WinRM (group_vars/linux.yml, windows.yml) |
| `mysql-root-password` | `vault_mysql_root_password` | Rol mysql — cont root |
| `mysql-wordpress-password` | `vault_mysql_wordpress_password` | Rol wordpress — user `wp_user` |
| `mysql-monitoring-password` | `vault_mysql_monitoring_password` | Rol monitoring — user `monitoring` |
| `mysql-api-password` | `vault_mysql_api_password` | Rol appserver — user `api_user` |
| `wordpress-admin-password` | `vault_wordpress_admin_password` | Rol wordpress — admin WP |
| `ansible-vault-password` | (parola vault — salvata la `~/.vault-pass`) | ansible.cfg `vault_password_file` |

`ansible.cfg` contine `vault_password_file = ~/.vault-pass` — playbook-urile ruleaza fara `--ask-vault-pass`.

---

## WinRM Bootstrap (Automat)

Scriptul `bicep/scripts/windows-winrm-bootstrap.ps1` ruleaza automat pe **vm-db-01** si **vm-fs-01**
la deployment via `Microsoft.Compute/virtualMachines/runCommands`.

Pasi: PSRemoting → WinRM service → HTTP listener:5985 → auth methods → firewall rule → network profile Private → CredSSP → test local.

**Transport Ansible:** `basic` (nu `ntlm`) — NTLM/MD4 este dezactivat implicit pe Ubuntu 22.04 cu OpenSSL 3.x.

**Nu este necesara nicio configurare manuala.**
Log: `C:\Logs\mediasrl\winrm-bootstrap-*.log`

---

## Deployment Scripts (ordine rulare)

```powershell
# 0. Bootstrap KV persistent (o singura data)
.\scripts\0-bootstrap-keyvault.ps1

# 1. Build Packer images (o singura data sau la actualizare imagini)
.\scripts\1-build-packer-images.ps1

# 2. Deploy infrastructura
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod

# 3. Deploy Ansible pe jumphost + creare Ansible Vault
.\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod

# 4. Configurare VM-uri (din jumphost, via RDP)
#    ansible-playbook playbooks/1-setup-ssh-keys.yml
#    ansible-playbook playbooks/2-site.yml
#    ansible-playbook playbooks/3-verify.yml
#    bash scripts/certbot-letsencrypt.sh
#    ansible-playbook playbooks/4-harden-nginx-ssl_ssllabs.com_ssltest.yml
#    bash scripts/demo-all-hardenings.sh      # SAU:
#    ansible-playbook playbooks/harden-security\(daca_nu_rulez_demouri\).yml
#    ansible-playbook playbooks/6-monitoring.yml

# 5. Teste infrastructura
.\scripts\4-test-infrastructure.ps1

# Teardown environment (KV persistent + IP-urile supravietuiesc)
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod
```

Toate scripturile genereaza loguri in `logs/`: `.log` (ANSI color), `.clean.log` (text), `.html` (raport colorat).
