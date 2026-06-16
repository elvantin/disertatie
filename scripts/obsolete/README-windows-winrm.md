# Windows WinRM Bootstrap — vm-db-01 / vm-fs-01

## Rezumat

**WinRM este configurat AUTOMAT** la deployment-ul Bicep — nu este nevoie de nicio interventie manuala.

Scriptul `bicep/scripts/windows-winrm-bootstrap.ps1` ruleaza pe Windows VMs la deployment
via resursa `Microsoft.Compute/virtualMachines/runCommands` din `bicep/modules/compute.bicep`.

---

## VM-uri afectate

| VM | OS | Rol |
|----|-----|-----|
| vm-db-01 | Windows Server 2022 | MySQL Community Server 8.0 |
| vm-fs-01 | Windows Server 2022 | SMB File Server |

---

## Ce face scriptul de bootstrap (automat)

Scriptul `bicep/scripts/windows-winrm-bootstrap.ps1` ruleaza la prima pornire a VM-ului:

1. Activeaza PowerShell Remoting (`Enable-PSRemoting -Force`)
2. Configureaza serviciul WinRM (pornire automata)
3. Creeaza listener HTTP pe portul 5985
4. Configureaza metodele de autentificare (Basic, Negotiate, Kerberos, CredSSP)
5. Permite trafic neencriptat pe HTTP (retea privata, acces restrictionat NSG)
6. Configureaza Windows Firewall (deschide portul 5985)
7. Seteaza profilul de retea la Private
8. Activeaza CredSSP pentru autentificare delegata
9. Testeaza configuratia WinRM local
10. Salveaza logul la `C:\Logs\mediasrl\winrm-bootstrap-*.log`

**Durata:** ~2-3 minute per VM (fara reboot)

---

## Unde se afla scriptul

```
bicep/scripts/windows-winrm-bootstrap.ps1
```

Scriptul este injectat in VM ca resursa Bicep in `bicep/modules/compute.bicep`:

```bicep
resource winrmRunCommand 'Microsoft.Compute/virtualMachines/runCommands@2023-09-01' = if (osType == 'Windows' && customScriptContent != '') {
  parent: vm
  name: 'WinRMBootstrap'
  properties: {
    source: {
      script: customScriptContent  // continutul windows-winrm-bootstrap.ps1
    }
    asyncExecution: false
    timeoutInSeconds: 600
  }
}
```

---

## Verificare dupa deployment

### Din jumphost (Ansible)

```bash
cd ~/ansible

# Test conectivitate WinRM
ansible windows -m win_ping

# Verbose (debug conectivitate)
ansible windows -m win_ping -vvv
```

### Pe VM (daca e necesar debug via RDP)

```powershell
# Verifica serviciul WinRM
Get-Service WinRM

# Verifica configuratia
Test-WSMan -ComputerName localhost
winrm get winrm/config

# Verifica listener-ul
Get-ChildItem WSMan:\localhost\Listener

# Verifica regula firewall
Get-NetFirewallRule -DisplayGroup 'Windows Remote Management'
```

### Log bootstrap

```powershell
# Via az run-command (de pe masina locala)
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-Content C:\Logs\mediasrl\winrm-bootstrap-*.log -Tail 50"
```

Log salvat la: `C:\Logs\mediasrl\winrm-bootstrap-YYYYMMDD-HHMMSS.log`

---

## Configuratie Ansible Inventory (group_vars/windows.yml)

```yaml
ansible_connection: winrm
ansible_winrm_transport: ntlm
ansible_winrm_server_cert_validation: ignore
ansible_port: 5985
ansible_user: azureadmin
ansible_password: "{{ vault_admin_password }}"  # din Ansible Vault (kv-mediasrl-persistent)
```

**Portul 5985 (WinRM HTTP) este restrictionat via NSG la snet-mgmt** — accesibil doar din jumphost.

---

## Troubleshooting

### WinRM nu raspunde

Verifica serviciul:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-Service WinRM | Select-Object Name,Status,StartType"
```

### Firewall blocheaza portul 5985

Verifica:

```powershell
az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts "Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' | Select-Object DisplayName,Enabled,Direction"
```

### Ansible: erori comune

| Eroare | Cauza | Solutie |
|--------|-------|---------|
| `No module named 'winrm'` | pywinrm nu e instalat pe jumphost | `sudo pip3 install pywinrm` |
| `401 Unauthorized` | Credentiale gresite | Verifica vault Ansible |
| `Connection timeout` | NSG blocheaza portul 5985 | Verifica `nsg-prod` permite mgmt→prod:5985 |
| `SSL certificate validation failed` | TLS mismatch | Adauga `ansible_winrm_server_cert_validation: ignore` |

### Resetare WinRM manuala (caz extrem)

Daca WinRM nu a fost configurat corect la deployment si VM-ul ruleaza deja,
poti rula scriptul manual via `az vm run-command`:

```powershell
$script = Get-Content -Path 'bicep\scripts\windows-winrm-bootstrap.ps1' -Raw

az vm run-command invoke `
  --resource-group rg-mediasrl-productie-swedencentral `
  --name vm-db-01 `
  --command-id RunPowerShellScript `
  --scripts $script
```

---

## Note de securitate

- WinRM HTTP (5985) este protejat la nivel NSG — accesibil **exclusiv** din `snet-mgmt` (10.10.12.0/24)
- Parola admin este stocata in Ansible Vault (`vault_admin_password`), preluata din `kv-mediasrl-persistent`
- Nu exista parole hardcodate in niciun fisier din repository
- Hardening WinRM (HTTPS, dezactivare Basic auth) se aplica via rolul Ansible `hardening`

---

## Fisiere relevante

| Fisier | Scop |
|--------|------|
| `bicep/scripts/windows-winrm-bootstrap.ps1` | Scriptul PowerShell de bootstrap WinRM |
| `bicep/modules/compute.bicep` | Resursa `runCommands` care ruleaza scriptul |
| `ansible/group_vars/windows.yml` | Variabile WinRM pentru Ansible |
| `ansible/inventory/azure_rm.yml` | Inventar dinamic (include Windows VMs) |
