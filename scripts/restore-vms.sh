#!/usr/bin/env bash
# ============================================================
# restore-vms.sh
# Restores all 6 VMs from OS disk snapshots created by snapshot-vms.sh
#
# Usage (from jumphost):
#   ~/scripts/restore-vms.sh <label-timestamp>
#   ~/scripts/restore-vms.sh pre-ansible-20260624-1430
#
#   # List available labels:
#   ~/scripts/restore-vms.sh --list
#
# Process per VM:
#   1. Deallocate VM
#   2. Create new managed disk from snapshot
#   3. Swap OS disk on VM
#   4. Start VM
#   5. Delete old OS disk (after confirmation)
#
# After restore, re-run:
#   ansible-playbook playbooks/1-setup-ssh-keys.yml   (SSH keys may be reset)
#   ansible-playbook playbooks/2-site.yml
# ============================================================

set -euo pipefail

RG="rg-mediasrl-productie-swedencentral"
SNAP_RG="rg-mediasrl-persistent"
LOCATION="swedencentral"
VMS=(vm-jmp-01 vm-web-01 vm-app-01 vm-cms-01 vm-db-01 vm-fs-01)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] $*${NC}"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ERROR: $*${NC}"; }

# ── List available snapshots ───────────────────────────────────────────────────
if [[ "${1:-}" == "--list" ]]; then
    echo ""
    echo "Available snapshots in ${SNAP_RG}:"
    echo ""
    az snapshot list \
        --resource-group "$SNAP_RG" \
        --query "[].{Name:name, Created:timeCreated, SizeGB:diskSizeGb}" \
        --output table 2>/dev/null | sort
    echo ""
    echo "Usage: $0 <label-timestamp>"
    echo "Example: $0 pre-ansible-20260624-1430"
    exit 0
fi

LABEL="${1:-}"
if [[ -z "$LABEL" ]]; then
    echo ""
    err "No label provided."
    echo ""
    echo "Usage: $0 <label-timestamp>"
    echo "       $0 --list   (show available snapshots)"
    exit 1
fi

# Verify Azure auth
az account show --query name -o tsv >/dev/null 2>&1 || {
    err "Not logged in to Azure. Run: az login --use-device-code"
    exit 1
}

# ── Validate all snapshots exist before touching any VM ───────────────────────
echo ""
echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}${BOLD}║  VM Restore from Snapshot — SC MEDIA SRL             ║${NC}"
echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "  This will REPLACE the OS disk on all 6 VMs."
warn "  All changes made after the snapshot was taken will be LOST."
echo ""
echo "  Label    : ${LABEL}"
echo "  VMs      : ${VMS[*]}"
echo ""

echo "  Validating snapshots exist..."
MISSING=0
for VM in "${VMS[@]}"; do
    SNAP_NAME="snap-${VM}-${LABEL}"
    EXISTS=$(az snapshot show \
        --resource-group "$SNAP_RG" \
        --name "$SNAP_NAME" \
        --query name -o tsv 2>/dev/null || true)
    if [[ -z "$EXISTS" ]]; then
        err "  Snapshot not found: ${SNAP_NAME}"
        ((MISSING++)) || true
    else
        echo -e "  ${GREEN}✓${NC} Found: ${SNAP_NAME}"
    fi
done

if [[ "$MISSING" -gt 0 ]]; then
    err "${MISSING} snapshot(s) missing. Run: $0 --list"
    exit 1
fi

echo ""
read -r -p "  Proceed with restore? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "  Aborted."
    exit 0
fi

echo ""
RESTORE_TIMESTAMP=$(date +%Y%m%d-%H%M)
declare -A OLD_DISK_IDS
declare -A NEW_DISK_NAMES

# ── Phase 1: Deallocate all VMs (in parallel) ─────────────────────────────────
echo ""
log "Phase 1 — Deallocating all VMs..."

for VM in "${VMS[@]}"; do
    # Save current OS disk ID before stopping
    OLD_DISK_IDS[$VM]=$(az vm show \
        --resource-group "$RG" \
        --name "$VM" \
        --query "storageProfile.osDisk.managedDisk.id" \
        --output tsv 2>/dev/null || true)

    log "  [${VM}] Deallocating..."
    az vm deallocate --resource-group "$RG" --name "$VM" --no-wait --output none
done

# Wait for all VMs to be deallocated
log "  Waiting for all VMs to deallocate..."
for VM in "${VMS[@]}"; do
    az vm wait --resource-group "$RG" --name "$VM" --custom "instanceView.statuses[?code=='PowerState/deallocated']" 2>/dev/null || true
    log "  [${VM}] ✓ Deallocated"
done

# ── Phase 2: Create new OS disks from snapshots (in parallel) ─────────────────
echo ""
log "Phase 2 — Creating new OS disks from snapshots..."

for VM in "${VMS[@]}"; do
    SNAP_NAME="snap-${VM}-${LABEL}"
    SNAP_ID=$(az snapshot show \
        --resource-group "$SNAP_RG" \
        --name "$SNAP_NAME" \
        --query id -o tsv)

    DISK_SKU=$(az snapshot show \
        --resource-group "$SNAP_RG" \
        --name "$SNAP_NAME" \
        --query "sku.name" -o tsv 2>/dev/null || echo "Premium_LRS")
    # Snapshots are stored as Standard_LRS; restored disks should match original
    DISK_SKU="Premium_LRS"

    NEW_DISK_NAME="${VM}-osdisk-restored-${RESTORE_TIMESTAMP}"
    NEW_DISK_NAMES[$VM]="$NEW_DISK_NAME"

    log "  [${VM}] Creating disk ${NEW_DISK_NAME} from snapshot..."
    az disk create \
        --resource-group "$RG" \
        --name "$NEW_DISK_NAME" \
        --source "$SNAP_ID" \
        --sku "$DISK_SKU" \
        --location "$LOCATION" \
        --tags "restored-from=${SNAP_NAME}" "restore-timestamp=${RESTORE_TIMESTAMP}" \
        --no-wait \
        --output none
done

# Wait for all disks to be created
log "  Waiting for new disks to be provisioned..."
for VM in "${VMS[@]}"; do
    DISK_NAME="${NEW_DISK_NAMES[$VM]}"
    az disk wait --resource-group "$RG" --name "$DISK_NAME" --created 2>/dev/null || true
    log "  [${VM}] ✓ Disk ready: ${DISK_NAME}"
done

# ── Phase 3: Swap OS disks ────────────────────────────────────────────────────
echo ""
log "Phase 3 — Swapping OS disks..."

for VM in "${VMS[@]}"; do
    NEW_DISK_ID=$(az disk show \
        --resource-group "$RG" \
        --name "${NEW_DISK_NAMES[$VM]}" \
        --query id -o tsv)

    log "  [${VM}] Swapping OS disk..."
    az vm update \
        --resource-group "$RG" \
        --name "$VM" \
        --os-disk "$NEW_DISK_ID" \
        --output none
    log "  [${VM}] ✓ OS disk swapped"
done

# ── Phase 4: Start all VMs (in parallel) ──────────────────────────────────────
echo ""
log "Phase 4 — Starting all VMs..."

for VM in "${VMS[@]}"; do
    az vm start --resource-group "$RG" --name "$VM" --no-wait --output none
done

log "  Waiting for all VMs to start..."
for VM in "${VMS[@]}"; do
    az vm wait --resource-group "$RG" --name "$VM" --custom "instanceView.statuses[?code=='PowerState/running']" 2>/dev/null || true
    log "  [${VM}] ✓ Running"
done

# ── Phase 5: Delete old OS disks ──────────────────────────────────────────────
echo ""
echo "  Old OS disks to delete (no longer attached):"
for VM in "${VMS[@]}"; do
    OLD_ID="${OLD_DISK_IDS[$VM]:-}"
    [[ -n "$OLD_ID" ]] && echo "    - $(basename "$OLD_ID")"
done
echo ""
read -r -p "  Delete old OS disks now? (yes/no): " DEL_CONFIRM
if [[ "$DEL_CONFIRM" == "yes" ]]; then
    for VM in "${VMS[@]}"; do
        OLD_ID="${OLD_DISK_IDS[$VM]:-}"
        if [[ -n "$OLD_ID" ]]; then
            log "  [${VM}] Deleting old disk: $(basename "$OLD_ID")"
            az disk delete --ids "$OLD_ID" --yes --no-wait --output none || true
        fi
    done
    log "  Old disks deleted."
else
    warn "  Old disks NOT deleted. Delete manually when confirmed restore is OK:"
    for VM in "${VMS[@]}"; do
        OLD_ID="${OLD_DISK_IDS[$VM]:-}"
        [[ -n "$OLD_ID" ]] && echo "    az disk delete --ids '${OLD_ID}' --yes"
    done
fi

# ── Also restore vm-fs-01 data disk if snapshot exists ────────────────────────
FS_DATA_SNAP="snap-vm-fs-01-datadisk-${LABEL}"
FS_DATA_EXISTS=$(az snapshot show \
    --resource-group "$SNAP_RG" \
    --name "$FS_DATA_SNAP" \
    --query name -o tsv 2>/dev/null || true)

if [[ -n "$FS_DATA_EXISTS" ]]; then
    echo ""
    warn "  Data disk snapshot found for vm-fs-01: ${FS_DATA_SNAP}"
    warn "  The data disk (D:\\) was NOT restored automatically (requires detach/reattach)."
    warn "  If SMB shares need reset, re-run: ansible-playbook 2-site.yml --limit fileserver"
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  Restore complete — all 6 VMs running                ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Next steps:"
echo "    1. SSH keys may have been reset — re-run:"
echo "       ansible-playbook playbooks/1-setup-ssh-keys.yml"
echo ""
echo "    2. Re-run full site deployment:"
echo "       ansible-playbook playbooks/2-site.yml"
echo ""
echo "    3. Verify:"
echo "       ansible-playbook playbooks/3-verify.yml"
echo ""
