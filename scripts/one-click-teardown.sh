#!/bin/bash
# =============================================================================
# 5C Security Lab - One-Click Teardown Script
#
# Destroys EVERYTHING in reverse dependency order:
#   1. Kubernetes resources (namespaces, RBAC)
#   2. Docker images in GCR
#   3. GKE cluster + all GCP infrastructure (via Terraform)
#   4. Local Terraform state
#   (Optional) 5. The entire GCP project
#
# Usage:
#   ./scripts/one-click-teardown.sh              # interactive
#   FORCE=yes ./scripts/one-click-teardown.sh    # skip confirmation
#   DELETE_PROJECT=yes ./scripts/one-click-teardown.sh  # also delete GCP project
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

section() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

# -----------------------------------------------------------------------------
# Step 0: Determine PROJECT_ID
# -----------------------------------------------------------------------------
cd "$PROJECT_ROOT/terraform" 2>/dev/null || true

PROJECT_ID="${PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || \
                 grep 'project_id' terraform.tfvars 2>/dev/null | head -1 | cut -d'"' -f2 || \
                 gcloud config get-value project 2>/dev/null || echo "")
fi

# -----------------------------------------------------------------------------
# Confirmation
# -----------------------------------------------------------------------------
section "5C Security Lab - Teardown"
echo -e "${RED}WARNING:${NC} This will PERMANENTLY DESTROY all resources in project:"
echo "  Project:  ${PROJECT_ID:-<not detected>}"
echo ""
echo "Resources to be destroyed:"
echo "  - Kubernetes namespaces (ai-governance, finance-prod)"
echo "  - Cluster roles and bindings"
echo "  - GKE cluster (vuln-gke-cluster) and node pools"
echo "  - VPC network, subnet, and firewall rules"
echo "  - GCS bucket and all stored data"
echo "  - IAM service account and key"
echo "  - Container images in GCR (vuln-app, vuln-ai-service)"
echo "  - Local Terraform state"

if [ "${DELETE_PROJECT:-no}" = "yes" ]; then
    echo "  - The entire GCP project: $PROJECT_ID"
fi

echo ""

if [ "${FORCE:-no}" != "yes" ]; then
    echo -n "Type 'destroy' to confirm: "
    read -r CONFIRM
    if [ "$CONFIRM" != "destroy" ]; then
        log "Aborted. No resources were destroyed."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# Step 1: Remove Kubernetes Resources
# -----------------------------------------------------------------------------
section "Step 1/4: Removing Kubernetes Resources"

if kubectl cluster-info >/dev/null 2>&1; then
    kubectl delete namespace ai-governance --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete namespace finance-prod --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete clusterrolebinding vuln-app-cluster-admin --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterrolebinding vuln-app-cluster-admin-prod --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterrole vuln-cluster-admin --ignore-not-found=true 2>/dev/null || true
    ok "Kubernetes resources removed"
else
    warn "kubectl not connected to a cluster — skipping K8s cleanup"
fi

# -----------------------------------------------------------------------------
# Step 2: Delete Container Images from GCR
# -----------------------------------------------------------------------------
section "Step 2/4: Removing Container Images"

if [ -n "$PROJECT_ID" ]; then
    for image in vuln-app vuln-ai-service; do
        if gcloud container images describe "gcr.io/${PROJECT_ID}/${image}:latest" >/dev/null 2>&1; then
            log "Deleting gcr.io/${PROJECT_ID}/${image}..."
            gcloud container images delete "gcr.io/${PROJECT_ID}/${image}:latest" \
                --quiet --force-delete-tags 2>/dev/null || warn "Failed to delete ${image}"
        fi
    done
    ok "GCR cleanup complete"
else
    warn "No project ID detected — skipping GCR cleanup"
fi

# -----------------------------------------------------------------------------
# Step 3: Terraform Destroy
# -----------------------------------------------------------------------------
section "Step 3/4: Destroying GCP Infrastructure (Terraform)"

cd "$PROJECT_ROOT/terraform"
if [ -f terraform.tfstate ] || [ -d .terraform ]; then
    log "Running terraform destroy (takes 5-10 minutes)..."
    terraform destroy -auto-approve || warn "terraform destroy encountered errors"
    ok "Infrastructure destroyed"
else
    warn "No Terraform state found — skipping destroy"
fi

# -----------------------------------------------------------------------------
# Step 4: Clean Local State
# -----------------------------------------------------------------------------
section "Step 4/4: Cleaning Local State"

rm -f "$PROJECT_ROOT/terraform/tfplan"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate.backup"
rm -rf "$PROJECT_ROOT/terraform/.terraform"
rm -f "$PROJECT_ROOT/terraform/.terraform.lock.hcl"
rm -f "$PROJECT_ROOT/app/governance.db"
ok "Local state cleaned"

# -----------------------------------------------------------------------------
# Optional: Delete the GCP Project Itself
# -----------------------------------------------------------------------------
if [ "${DELETE_PROJECT:-no}" = "yes" ] && [ -n "$PROJECT_ID" ]; then
    section "Bonus: Deleting GCP Project"
    log "Scheduling project $PROJECT_ID for deletion (30-day recovery window)..."
    gcloud projects delete "$PROJECT_ID" --quiet || warn "Project deletion failed"
    ok "Project $PROJECT_ID scheduled for deletion"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
section "TEARDOWN COMPLETE"
echo ""
echo "  All lab resources have been destroyed."
echo ""
if [ "${DELETE_PROJECT:-no}" != "yes" ]; then
    echo "  The GCP project '$PROJECT_ID' still exists (no cost if empty)."
    echo "  To delete it too: gcloud projects delete $PROJECT_ID"
fi
echo ""
echo "  To redeploy: ./scripts/one-click-deploy.sh"
echo ""
