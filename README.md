# Proiectarea, implementarea si securizarea unei infrastructuri cloud automatizate in Microsoft Azure utilizand Bicep, Packer si Ansible

**Studiu de caz privind adoptarea Infrastructure as Code si DevOps intr-un mediu enterprise**

Lucrare de disertatie — Master, 2026

---

## Descriere

Acest repository contine codul sursa si documentatia aferenta proiectului de disertatie. Proiectul implementeaza o infrastructura cloud completa in Microsoft Azure pentru **SC MEDIA SRL**, o companie de PR si Marketing, utilizand principiile Infrastructure as Code (IaC) si DevOps.

Infrastructura include 5 masini virtuale (2x Windows Server 2022, 3x Rocky Linux 10), configurate automat prin pipeline-uri CI/CD.

## Tehnologii utilizate

| Tehnologie | Rol |
|-----------|-----|
| **Bicep** | Definirea declarativa a infrastructurii Azure (IaC) |
| **Packer** | Construirea imaginilor golden (Rocky Linux 10, Windows Server 2022) |
| **Ansible** | Automatizarea configurarii post-provisioning |
| **Azure DevOps** | Versionare cod (Git) si pipeline-uri CI/CD |
| **Azure Monitor** | Monitorizare si loguri centralizate |
| **Azure Key Vault** | Gestionarea secretelor si certificatelor |
| **Azure Policy** | Guvernanta si conformitate |

## Structura repository-ului

```
IT/
├── packer/                     # Template-uri Packer (golden images)
│   ├── rocky-linux/            #   Rocky Linux 10
│   └── windows-server/         #   Windows Server 2022
│
├── bicep/                      # Module Bicep (Infrastructure as Code)
│   ├── main.bicep              #   Orchestrator principal
│   ├── modules/                #   Module individuale (networking, compute, etc.)
│   └── parameters/             #   Fisiere parametri per mediu (prod/dev)
│
├── ansible/                    # Configurare automata Ansible
│   ├── inventory/              #   Inventare (productie, dezvoltare)
│   ├── playbooks/              #   Playbook-uri per rol
│   ├── roles/                  #   Roluri Ansible (common, nginx, mysql, etc.)
│   └── files/                  #   Fisiere statice (website)
│
├── pipelines/                  # Pipeline-uri Azure DevOps (YAML)
│   └── templates/              #   Pasi comuni reutilizabili
│
├── docs/                       # Documentatie
│   ├── PLAN_PROIECT.md         #   Planul complet al proiectului
│   └── disertatie/             #   Capitole si figuri disertatie
│
├── .gitignore
└── README.md
```

## Arhitectura mediului

- **VNet:** `vnet-media-prod` (10.10.0.0/20)
- **Subnet Production:** `snet-prod` (10.10.10.0/24) — vm-web-01, vm-app-01, vm-cms-01, vm-db-01
- **Subnet Management:** `snet-mgmt` (10.10.12.0/24) — vm-jmp-01 (Jumphost)
- **Subnet Dev:** `snet-dev` (10.10.11.0/24) — mediu de dezvoltare/testare

## Quick Start

### Cerinte preliminare

- Azure CLI (`az --version`)
- Bicep CLI (`az bicep version`)
- Packer (`packer --version`)
- Ansible (`ansible --version`) — necesita Linux (WSL2 sau VM)
- Visual Studio Code + extensii (Bicep, Ansible, Azure)

### Autentificare Azure

```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
```

### Flux de lucru

1. **Packer** — Construieste imaginile golden si le publica in Azure Compute Gallery
2. **Bicep** — Deploys infrastructura Azure (VNet, VM-uri, NSG, Key Vault, Monitor)
3. **Ansible** — Configureaza VM-urile (nginx, MySQL, WordPress, Postfix, hardening)

---

*Proiect realizat de SC IT SECURITY SRL pentru SC MEDIA SRL*
