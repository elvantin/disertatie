# Infrastructure Summary — SC MEDIA SRL

**Data:** 2026-06-12

---

## Arhitectura curenta (6 VM-uri)

| VM | OS | Rol | Size |
|----|----|-----|------|
| vm-jmp-01 | Ubuntu 22.04 LTS | Jumphost + Ansible Control Node | Standard_B4ls_v2 |
| vm-web-01 | Ubuntu 22.04 LTS | nginx reverse proxy + SSL | Standard_B2s |
| vm-app-01 | Ubuntu 22.04 LTS | REST API (port 8080) | Standard_B2s |
| vm-cms-01 | Ubuntu 22.04 LTS | WordPress + Postfix | Standard_B2s |
| vm-db-01  | Windows Server 2022 | MySQL Community 8.0 | Standard_B2s |
| vm-fs-01  | Windows Server 2022 | SMB File Server | Standard_B2s |

---

## Componente Azure

| Resursa | Nume | RG |
|---------|------|----|
| VNet | vnet-mediasrl-productie (10.10.0.0/20) | productie |
| Key Vault (infra) | kv-mediasrl-productie | productie |
| Key Vault (secrete) | kv-mediasrl-persistent | persistent |
| Log Analytics | log-mediasrl-productie | productie |
| Compute Gallery | gal_mediasrl | packer |
| IP public jumphost | pip-vm-jmp-01 | persistent |
| IP public webserver | pip-vm-web-01 | persistent |

---

## Stare curenta componente

### Bicep (IaC)
- Deployment via `scripts/2-deploy-teardown-bicep.ps1`
- IP admin detectat automat + adaugat la whitelist NSG
- WinRM bootstrap Windows: automat via `runCommands` (nu CSE — limita cmd.exe depasita)
- Azure Backup (RSV): **dezactivat** — vault blocheaza teardown-ul, in investigare
- Access policy jumphost MSI → kv-mediasrl-persistent: configurat via Bicep

### Packer (Golden Images)
- 3 image definitions in `gal_mediasrl`
- `imgdef-ubuntu2204` — Ubuntu base hardened
- `imgdef-ubuntu2204-jumphost` — Ubuntu + XFCE + Ansible + Azure CLI
- `imgdef-winserver2022` — Windows Server 2022 + WinRM pre-configurat

### Ansible (Config Management)
- Inventar dinamic Azure (`azure_rm.yml`) cu `auth_source: msi` (fara `az login`)
- Vault automat: `ansible/scripts/create-ansible-vault.sh` preia secretele din KV via MSI
- Vault password: `~/.vault-pass` (generat de scriptul de bootstrap)
- Ansible Galaxy collections pre-installed in imaginea Packer

### Scripts (PowerShell — ordine rulare)

| Script | Scop | Cand |
|--------|------|------|
| `0-bootstrap-keyvault.ps1` | Creeaza KV persistent + populeaza secrete | O singura data |
| `1-build-packer-images.ps1` | Build imagini golden in Azure Compute Gallery | La actualizare imagini |
| `2-deploy-teardown-bicep.ps1` | Deploy sau teardown infrastructura | La fiecare deploy |
| `3-deploy-ansible-to-jumphost.ps1` | Copiaza ansible/ pe jumphost + ruleaza create-ansible-vault.sh | Dupa deploy |
| `4-test-infrastructure.ps1` | Teste Azure (resurse, VM-uri, NSG, conectivitate) | Dupa deploy |
| `get-vm-ips.ps1` | Afiseaza IP-uri + genereaza hosts.ini static | Utilitar |

Toate scripturile genereaza log HTML + log text in `logs/`.

### HTML Logs
Fiecare script genereaza un raport HTML colapsibil in `logs/`:
- Output-ul comenzilor az CLI este capturat in blocuri `<details>` expandabile
- Logul e scris intotdeauna, indiferent daca scriptul se termina cu eroare sau succes (trap block)

---

## Probleme cunoscute / In lucru

- **Azure Backup**: modulele `backup.bicep` si `backup-vm.bicep` exista dar sunt dezactivate in `main.bicep`. Recovery Services Vault nu poate fi sters fortat la teardown. In investigare.
- **Ansible roles**: directoarele exista cu `.gitkeep`, continutul rolurilor urmeaza a fi implementat.
- **Playbooks**: `playbooks/.gitkeep` — playbook-urile Ansible urmeaza a fi scrise.
