#!/bin/bash
# =============================================================================
# 5C Security Lab - Force Cleanup Script (State-less)
#
# Deletes all lab resources via gcloud CLI when Terraform state is missing
# or corrupted. Use this to recover from state drift and start fresh.
#
# Usage:
#   export PROJECT_ID="your-project-id"
#   ./scripts/force-cleanup-gcp.sh
# =============================================================================

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
[ -n "$PROJECT_ID" ] || fail "Set PROJECT_ID env var or configure gcloud default project"

REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  Force Cleanup for Project: $PROJECT_ID${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "${RED}WARNING:${NC} This will delete ALL lab resources via gcloud."
echo "  Project:  $PROJECT_ID"
echo "  Region:   $REGION"
echo ""
echo -n "Type 'cleanup' to confirm: "
read -r CONFIRM
[ "$CONFIRM" = "cleanup" ] || { echo "Aborted."; exit 0; }
echo ""

# ---- GKE cluster (must come first - blocks network/SA deletion) ----
log "Checking for GKE cluster..."
if gcloud container clusters describe vuln-gke-cluster --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
    log "Deleting GKE cluster vuln-gke-cluster (takes 3-5 min)..."
    gcloud container clusters delete vuln-gke-cluster \
        --zone="$ZONE" --project="$PROJECT_ID" --quiet
    ok "Cluster deleted"
else
    ok "Cluster does not exist"
fi

# ---- GCS Bucket (must be emptied before deletion) ----
BUCKET="vuln-ai-governance-data-${PROJECT_ID}"
log "Checking for GCS bucket $BUCKET..."
if gsutil ls -b "gs://${BUCKET}" >/dev/null 2>&1; then
    log "Emptying and deleting bucket $BUCKET..."
    gsutil -m rm -rf "gs://${BUCKET}/**" 2>/dev/null || true
    gsutil rb "gs://${BUCKET}" 2>/dev/null || warn "Bucket delete failed (may already be gone)"
    ok "Bucket deleted"
else
    ok "Bucket does not exist"
fi

# ---- Firewall rules ----
for rule in allow-internal allow-ssh allow-nodeports allow-mgmt; do
    FW="vuln-network-${rule}"
    log "Checking firewall $FW..."
    if gcloud compute firewall-rules describe "$FW" --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute firewall-rules delete "$FW" --project="$PROJECT_ID" --quiet
        ok "Firewall $FW deleted"
    fi
done

# ---- Subnet ----
log "Checking for subnet vuln-subnet..."
if gcloud compute networks subnets describe vuln-subnet --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud compute networks subnets delete vuln-subnet --region="$REGION" --project="$PROJECT_ID" --quiet
    ok "Subnet deleted"
fi

# ---- VPC Network ----
log "Checking for network vuln-network..."
if gcloud compute networks describe vuln-network --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud compute networks delete vuln-network --project="$PROJECT_ID" --quiet
    ok "Network deleted"
fi

# ---- IAM bindings (remove before SA can be deleted cleanly) ----
SA_EMAIL="vuln-gke-node-sa@${PROJECT_ID}.iam.gserviceaccount.com"
log "Removing IAM bindings for $SA_EMAIL..."
for role in roles/editor roles/storage.admin roles/aiplatform.admin; do
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" --quiet 2>/dev/null || true
done
ok "IAM bindings removed"

# ---- Service Account ----
log "Checking for service account $SA_EMAIL..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts delete "$SA_EMAIL" --project="$PROJECT_ID" --quiet
    ok "Service account deleted"
fi

# ---- GCR images ----
for image in vuln-app vuln-ai-service; do
    if gcloud container images describe "gcr.io/${PROJECT_ID}/${image}:latest" >/dev/null 2>&1; then
        log "Deleting GCR image $image..."
        gcloud container images delete "gcr.io/${PROJECT_ID}/${image}:latest" \
            --quiet --force-delete-tags 2>/dev/null || true
    fi
done

# ---- Clean local Terraform state ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
log "Cleaning local Terraform state..."
rm -f "$PROJECT_ROOT/terraform/tfplan"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate.backup"
rm -rf "$PROJECT_ROOT/terraform/.terraform"
rm -f "$PROJECT_ROOT/terraform/.terraform.lock.hcl"
ok "Local state cleaned"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Force Cleanup Complete${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "You can now redeploy:  ./scripts/one-click-deploy.sh"
echo ""
