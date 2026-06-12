# Infrastructure Summary — SC MEDIA SRL

**Data:** 2026-06-13

---

## Arhitectura curentă (6 VM-uri)

| VM | OS | Rol | Size |
|----|----|-----|------|
| vm-jmp-01 | Ubuntu 22.04 LTS | Jumphost + Ansible Control Node + xRDP | Standard_B4ls_v2 |
| vm-web-01 | Ubuntu 22.04 LTS | nginx reverse proxy + SSL/TLS | Standard_B2s |
| vm-app-01 | Ubuntu 22.04 LTS | Application server (REST API port 8080) | Standard_B2s |
| vm-cms-01 | Ubuntu 22.04 LTS | WordPress + PHP-FPM + Postfix | Standard_B2s |
| vm-db-01  | Windows Server 2022 | MySQL Community Server 8.0 | Standard_B2s |
| vm-fs-01  | Windows Server 2022 | SMB File Server (LanmanServer) | Standard_B2s |

---

## Componente Azure

| Resursă | Nume | Resource Group |
|---------|------|----------------|
| VNet | vnet-mediasrl-productie (10.10.0.0/20) | rg-mediasrl-productie-swedencentral |
| Key Vault (infra) | kv-mediasrl-productie | rg-mediasrl-productie-swedencentral |
| Key Vault (secrete) | kv-mediasrl-persistent | rg-mediasrl-persistent |
| Log Analytics | log-mediasrl-productie | rg-mediasrl-productie-swedencentral |
| Compute Gallery | gal_mediasrl | rg-mediasrl-packer |
| IP public jumphost | pip-vm-jmp-01 | rg-mediasrl-persistent |
| IP public webserver | pip-vm-web-01 | rg-mediasrl-persistent |

---

## Stare curentă componente

### Bicep (IaC) — 14 module

- Deployment via `scripts/2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod`
- Scope: subscription — creează `rg-mediasrl-productie-swedencentral`
- IP admin detectat automat + adăugat la whitelist NSG
- WinRM bootstrap Windows: automat via `Microsoft.Compute/virtualMachines/runCommands`
- MSI jumphost → `kv-mediasrl-persistent`: access policy configurat via `kv-access-policy.bicep`
- Azure Backup (RSV): **dezactivat** — `backup.bicep` și `backup-vm.bicep` există dar sunt comentate în `main.bicep`

### Packer (Golden Images) — 3 image definitions

| Image | Conținut |
|-------|----------|
| `imgdef-ubuntu2204` | Ubuntu 22.04 LTS base + hardened (unattended-upgrades, auditd) |
| `imgdef-ubuntu2204-jumphost` | Ubuntu + XFCE4 + xRDP + Ansible + Azure CLI + Galaxy collections |
| `imgdef-winserver2022` | Windows Server 2022 + WinRM pre-configurat + Chocolatey |

### Ansible (Config Management) — 13 roluri, 7 playbooks

**Roluri implementate:**

| Rol | OS | Funcție |
|-----|----|---------|
| `common` | Linux | Baseline: timezone, NTP, unattended-upgrades, auditd |
| `jumphost` | Linux | XFCE4, xRDP, Azure CLI, Ansible, Galaxy collections |
| `nginx` | Linux | Reverse proxy, virtual hosts, rate limiting config |
| `appserver` | Linux | Configurare aplicație port 8080 |
| `wordpress` | Linux | WordPress + PHP-FPM + WP-CLI |
| `postfix` | Linux | SMTP relay + DKIM/SPF |
| `mysql` | Windows | MySQL 8.0, creare DB/user, configurare securizată |
| `fileserver` | Windows | SMB shares, NTFS permissions |
| `hardening` | Linux | CIS Benchmark L1: sysctl, PAM, SSH baseline |
| `fail2ban` | Linux | Jail SSH + nginx, 5 eșecuri → ban 1h |
| `ssh-hardening` | Linux | Curve25519, ChaCha20, ECDH — algoritmi slabi eliminați |
| `modsecurity` | Linux | ModSecurity + OWASP CRS 3.2.1 pe nginx |
| `monitoring` | Linux/Win | Azure Monitor Agent + DCR, Log Analytics workspace |

**Playbooks:**

| Playbook | Scop |
|----------|------|
| `1-setup-ssh-keys.yml` | Distribuire SSH keys pe VM-urile Linux |
| `2-site.yml` | Configurare completă: common, jumphost, nginx, appserver, wordpress, mysql, fileserver |
| `3-verify.yml` | Verificare servicii, conectivitate, răspuns HTTP |
| `4-harden-nginx-ssl.yml` | Let's Encrypt (certbot), HSTS, OCSP stapling |
| `5-harden-security.yml` | fail2ban, ssh-hardening, modsecurity, mysql-hardening (TDE) |
| `6-monitoring.yml` | Azure Monitor Agent + Data Collection Rules |
| `bootstrap-windows-winrm.yml` | Bootstrap WinRM (fallback manual) |

**Alte componente Ansible:**
- Inventar dinamic: `inventory/azure_rm.yml` cu `auth_source: msi` (fără `az login`)
- Vault automat: `scripts/create-ansible-vault.sh` preia secretele din KV via MSI
- Vault password: `~/.vault-pass` (generat la bootstrap)
- Certbot wrapper: `scripts/certbot-letsencrypt.sh`

### Scripts (PowerShell — ordinea de rulare)

| # | Script | Scop | Când |
|---|--------|------|------|
| 0 | `0-bootstrap-keyvault.ps1` | Creare KV persistent + 7 secrete | O singură dată |
| 1 | `1-build-packer-images.ps1` | Build 3 imagini golden în Compute Gallery | La actualizare imagini |
| 2 | `2-deploy-teardown-bicep.ps1` | Deploy / teardown infrastructură Bicep | La fiecare deploy |
| 3 | `3-deploy-ansible-to-jumphost.ps1` | SCP ansible/ pe jumphost + vault bootstrap | După deploy |
| 4 | `4-test-infrastructure.ps1` | Teste Azure: resurse, VM-uri, NSG, conectivitate | Verificare post-deploy |
| — | `get-vm-ips.ps1` | Afișează IP-uri + generează `hosts.ini` static | Utilitar |

Toate scripturile generează log HTML + log text în `logs/` via `scripts/lib/Write-Log.ps1`.

---

## Security Hardening Stack

| Componentă | Configurare | VM target |
|-----------|-------------|-----------|
| nginx rate limiting | `/wp-login.php`, `/api/` — 10 req/min, burst 5 | vm-web-01 |
| fail2ban | SSH + nginx: 5 eșecuri → ban 1h (`iptables`) | toate Linux |
| SSH hardening | KexAlgs: curve25519; Ciphers: chacha20, aes256-gcm; MACs: hmac-sha2-512 | toate Linux |
| ModSecurity WAF | OWASP CRS 3.2.1 — DetectionOnly→Enforcement; blochează SQLi, XSS, traversal | vm-web-01 |
| MySQL TDE | InnoDB tablespace encryption (`keyring_file`); `local_infile=OFF`; anonimi eliminați | vm-db-01 |
| SSL/TLS | Let's Encrypt wildcard; HSTS 31536000s; OCSP stapling; TLS 1.2/1.3 only | vm-web-01 |

### Demo scripts securitate

Locație: `ansible/scripts/demo-*.sh`

| Script | Ce demonstrează |
|--------|-----------------|
| `demo-1-rate-limiting.sh` | 429 Too Many Requests după burst pe /wp-login.php |
| `demo-2-fail2ban.sh` | Ban IP automat după 5 eșecuri SSH simulate |
| `demo-3-ssh-hardening.sh` | `ssh -Q kex/cipher/mac` înainte vs. după |
| `demo-4-modsecurity.sh` | HTTP 403 la SQLi / XSS / path traversal |
| `demo-5-mysql-hardening.sh` | Anonimi eliminați + TDE: fișier `.ibd` criptat |
| `demo-all-hardenings.sh` | Rulare secvențială demo 1-5 + raport HTML master |

Fiecare demo generează un **raport HTML** (`logs/security-demos/`) via `scripts/lib/generate-demo-html.py` — dark theme, secțiuni BEFORE/AFTER/DIFF colapsibile, statistici.

---

## Probleme cunoscute

- **Azure Backup (RSV)**: modulele există (`backup.bicep`, `backup-vm.bicep`) dar sunt dezactivate în `main.bicep`. Recovery Services Vault blochează teardown-ul forțat. Dezactivat deliberat pentru proiect academic.
- **`vm-script-extension.bicep`**: modul existent, neutilizat activ — WinRM se face via `runCommands` direct în `compute.bicep`.
