# Jumphost Bootstrap — vm-jmp-01

## Rezumat

**Bootstrap-ul jumphostului este complet AUTOMAT** — nu este nevoie de nicio interventie manuala.

Toate uneltele necesare (XFCE, xRDP, Ansible, Azure CLI, VS Code, pywinrm etc.) sunt
pre-instalate in imaginea `imgdef-ubuntu2204-jumphost` construita cu Packer.
La deployment-ul Bicep, VM-ul porneste direct cu toate componentele functionale.

---

## Specificatii VM

| Atribut | Valoare |
|---------|---------|
| Size | Standard_B4ls_v2 (4 vCPU, 8GB RAM) |
| OS | Ubuntu 22.04 LTS (din imaginea Packer `imgdef-ubuntu2204-jumphost`) |
| Disk | 64GB Standard SSD |
| Desktop | XFCE (lightweight, optimizat pentru xRDP) |
| Browser | Firefox ESR |
| Firewall | firewalld |
| IP public | Persistent (`pip-vm-jmp-01` in `rg-mediasrl-persistent`) |

---

## Ce contine imaginea Packer (imgdef-ubuntu2204-jumphost)

Imaginea este construita o singura data (sau la actualizare) cu `scripts/1-build-packer-images.ps1`
si stocata in `gal_mediasrl`. Contine pre-instalat:

- XFCE Desktop Environment + xRDP (port 3389)
- Ansible cu `azure.azcollection` (inventar dinamic Azure via MSI)
- `python3-winrm` / `pywinrm` (conectivitate WinRM la Windows VMs)
- Azure CLI
- VS Code (Microsoft repository)
- Firefox ESR (Mozilla Team PPA)
- Remmina RDP client
- Git, vim, htop, tmux, jq, curl, wget si alte utilitare DevOps
- `firewalld` (UFW dezinstalat)
- `xrdp` configurat pentru XFCE

---

## Conectare dupa deployment

### 1. Obtine IP-ul public

```powershell
az network public-ip show -g rg-mediasrl-persistent -n pip-vm-jmp-01 --query ipAddress -o tsv
```

### 2. Conectare RDP

```powershell
mstsc /v:<IP_JUMPHOST>
```

Credentiale:
- **Username:** `azureadmin`
- **Password:** secretul `vm-admin-password` din `kv-mediasrl-persistent`

```powershell
# Obtine parola din Key Vault
az keyvault secret show --vault-name kv-mediasrl-persistent --name vm-admin-password --query value -o tsv
```

---

## Dupa conectare

Dupa prima conectare RDP, directorul `~/ansible` este populat automat de
`scripts/3-deploy-ansible-to-jumphost.ps1` (pasul urmator in deployment).

```bash
cd ~/ansible

# Verifica inventarul dinamic
ansible-inventory --list

# Verifica conectivitate Linux VMs
ansible all -m ping

# Verifica conectivitate Windows VMs
ansible windows -m win_ping

# Deploy configuratie
ansible-playbook playbooks/2-site.yml
```

---

## Managed Identity (MSI)

Jumphostul are Managed Identity configurata cu:
- **Reader** pe `rg-mediasrl-persistent`
- **Key Vault Secrets User** pe `kv-mediasrl-persistent`

Aceasta permite:
- `az login --identity` — autentificare fara credentiale hardcodate
- Inventarul Ansible `azure_rm.yml` cu `auth_source: msi` — fara `az login` separat
- `create-ansible-vault.sh` — preia secretele din KV via MSI

---

## Troubleshooting

### RDP nu functioneaza

```bash
# Verifica xRDP via az run-command
az vm run-command invoke \
  --resource-group rg-mediasrl-productie-swedencentral \
  --name vm-jmp-01 \
  --command-id RunShellScript \
  --scripts "systemctl status xrdp; firewall-cmd --list-all"
```

Verifica:
- NSG-ul `nsg-mgmt` permite portul 3389 de la IP-ul tau
- xRDP ruleaza: `systemctl status xrdp`
- Firewall: `firewall-cmd --list-all` (trebuie sa apara portul `3389/tcp`)

### Reconectare se inchide imediat

Desktop-ul nu este pornit corect:

```bash
az vm run-command invoke \
  --resource-group rg-mediasrl-productie-swedencentral \
  --name vm-jmp-01 \
  --command-id RunShellScript \
  --scripts "cat /etc/xrdp/startwm.sh"
```

Linia din `startwm.sh` trebuie sa contina `exec startxfce4`.

### Firefox nu functioneaza

```bash
sudo add-apt-repository -y ppa:mozillateam/ppa
sudo apt update
sudo apt install -y firefox-esr
```

### Remmina — conexiune la Windows se inchide

1. Deschide Remmina
2. Editeaza conexiunea
3. Advanced → Security: **NLA protocol security**
4. Advanced → Ignore certificate: **YES**

### Managed Identity nu functioneaza

Verifica ca VM-ul are MSI activata:

```powershell
az vm identity show -g rg-mediasrl-productie-swedencentral -n vm-jmp-01
```

Verifica access policy in KV:

```powershell
az keyvault show -n kv-mediasrl-persistent --query properties.accessPolicies
```

---

## Reconstruire imagine (daca e necesar)

Daca imaginea Packer trebuie reconstruita:

```powershell
.\scripts\1-build-packer-images.ps1
```

Urmat de re-deployment VM:

```powershell
.\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment prod
.\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod
```

---

**Nota:** Scriptul `3-bootstrap-windows-winrm.ps1` si `4-deploy-ansible-to-jumphost.ps1`
au fost redenumite ca `3-deploy-ansible-to-jumphost.ps1` si `4-test-infrastructure.ps1`.
Bootstrap-ul WinRM este acum automat via Bicep `runCommands`.
