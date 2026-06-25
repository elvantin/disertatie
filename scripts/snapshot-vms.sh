#!/usr/bin/env bash
# ============================================================
# snapshot-vms.sh
# Creates OS disk snapshots for all 6 VMs
#
# Run this BEFORE 2-site.yml to capture the post-Packer,
# pre-Ansible state. Use restore-vms.sh to roll back.
#
# Usage (from jumphost, az login already done):
#   chmod +x ~/ansible/../scripts/snapshot-vms.sh
#   ~/scripts/snapshot-vms.sh
#   ~/scripts/snapshot-vms.sh --label "pre-ansible"
#
# Snapshots are stored in rg-mediasrl-persistent so they
# survive even if the main resource group is deleted/recreated.
# ============================================================

set -euo pipefail

RG="rg-mediasrl-productie-swedencentral"
SNAP_RG="rg-mediasrl-persistent"
LABEL="${1:---label}"
LABEL="${LABEL#--label}"
LABEL="${LABEL:-pre-ansible}"
TIMESTAMP=$(date +%Y%m%d-%H%M)
TAG="${LABEL}-${TIMESTAMP}"

VMS=(vm-jmp-01 vm-web-01 vm-app-01 vm-cms-01 vm-db-01 vm-fs-01)

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
info() { echo -e "${CYAN}$*${NC}"; }

echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║  VM Snapshot — SC MEDIA SRL                          ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "  Source RG   : ${RG}"
info "  Snapshot RG : ${SNAP_RG}"
info "  Label       : ${TAG}"
info "  VMs         : ${VMS[*]}"
echo ""

# Verify Azure auth
ACCOUNT=$(az account show --query name -o tsv 2>/dev/null) || {
    echo "ERROR: Not logged in to Azure. Run: az login --use-device-code"
    exit 1
}
log "Azure account: ${ACCOUNT}"
echo ""

declare -A SNAP_NAMES

for VM in "${VMS[@]}"; do
    info "  [${VM}] Querying OS disk..."

    DISK_ID=$(az vm show \
        --resource-group "$RG" \
        --name "$VM" \
        --query "storageProfile.osDisk.managedDisk.id" \
        --output tsv 2>/dev/null) || {
        echo "  WARNING: Could not query ${VM} (VM may not exist yet). Skipping."
        continue
    }

    DISK_NAME=$(basename "$DISK_ID")
    SNAP_NAME="snap-${VM}-${TAG}"

    # Skip if snapshot with same name already exists
    EXISTS=$(az snapshot show \
        --resource-group "$SNAP_RG" \
        --name "$SNAP_NAME" \
        --query name -o tsv 2>/dev/null || true)

    if [[ -n "$EXISTS" ]]; then
        echo "  [${VM}] Snapshot ${SNAP_NAME} already exists — skipping."
        SNAP_NAMES[$VM]="$SNAP_NAME"
        continue
    fi

    info "  [${VM}] Creating snapshot: ${SNAP_NAME}"
    info "         Source disk: ${DISK_NAME}"

    az snapshot create \
        --resource-group "$SNAP_RG" \
        --name "$SNAP_NAME" \
        --source "$DISK_ID" \
        --sku Standard_LRS \
        --tags "vm=${VM}" "label=${LABEL}" "timestamp=${TIMESTAMP}" "source-rg=${RG}" \
        --output none

    log "  [${VM}] ✓ Snapshot created: ${SNAP_NAME}"
    SNAP_NAMES[$VM]="$SNAP_NAME"
done

# Also snapshot vm-fs-01 data disk (D:\) — contains SMB shares initialized by Ansible
FS_VM="vm-fs-01"
DATA_DISK_COUNT=$(az vm show \
    --resource-group "$RG" \
    --name "$FS_VM" \
    --query "length(storageProfile.dataDisks)" \
    --output tsv 2>/dev/null || echo "0")

if [[ "$DATA_DISK_COUNT" -gt 0 ]]; then
    DATA_DISK_ID=$(az vm show \
        --resource-group "$RG" \
        --name "$FS_VM" \
        --query "storageProfile.dataDisks[0].managedDisk.id" \
        --output tsv 2>/dev/null || true)

    if [[ -n "$DATA_DISK_ID" ]]; then
        DATA_SNAP_NAME="snap-${FS_VM}-datadisk-${TAG}"
        EXISTS=$(az snapshot show \
            --resource-group "$SNAP_RG" \
            --name "$DATA_SNAP_NAME" \
            --query name -o tsv 2>/dev/null || true)

        if [[ -z "$EXISTS" ]]; then
            info "  [${FS_VM}] Creating data disk snapshot: ${DATA_SNAP_NAME}"
            az snapshot create \
                --resource-group "$SNAP_RG" \
                --name "$DATA_SNAP_NAME" \
                --source "$DATA_DISK_ID" \
                --sku Standard_LRS \
                --tags "vm=${FS_VM}" "disk=data" "label=${LABEL}" "timestamp=${TIMESTAMP}" \
                --output none
            log "  [${FS_VM}] ✓ Data disk snapshot created: ${DATA_SNAP_NAME}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  All snapshots created successfully                  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Label used: ${TAG}"
echo "  To list all snapshots:"
echo "    az snapshot list -g ${SNAP_RG} -o table"
echo ""
echo "  To rollback all VMs to this snapshot:"
echo "    ~/scripts/restore-vms.sh ${TAG}"
echo ""
