#!/bin/bash
# =============================================================================
# 5C Security Lab - Complete Cleanup Script
# Destroys ALL lab resources in reverse dependency order
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================="
echo "  5C Security Lab - Cleanup"
echo "============================================="
echo ""
echo "WARNING: This will PERMANENTLY DESTROY all lab resources:"
echo "  - Kubernetes namespaces and all workloads"
echo "  - GKE cluster and node pools"
echo "  - GCS buckets and all stored data"
echo "  - IAM service accounts and keys"
echo "  - VPC network and firewall rules"
echo "  - Container images in GCR"
echo "  - Local Terraform state"
echo ""
echo -n "Type 'destroy' to confirm: "
read -r CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted. No resources were destroyed."
    exit 0
fi

echo ""

# Get project ID
cd "$PROJECT_ROOT/terraform"
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || grep 'project_id' terraform.tfvars 2>/dev/null | head -1 | cut -d'"' -f2 || echo "")

# ─── Step 1: Delete Kubernetes Resources ───
echo "--- Step 1: Removing Kubernetes Resources ---"
if kubectl cluster-info >/dev/null 2>&1; then
    kubectl delete namespace ai-governance --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete namespace finance-prod --ignore-not-found=true --timeout=60s 2>/dev/null || true
    kubectl delete clusterrolebinding vuln-app-cluster-admin --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterrolebinding vuln-app-cluster-admin-prod --ignore-not-found=true 2>/dev/null || true
    kubectl delete clusterrole vuln-cluster-admin --ignore-not-found=true 2>/dev/null || true
    echo "Kubernetes resources removed."
else
    echo "kubectl not connected to a cluster, skipping K8s cleanup."
fi

# ─── Step 2: Delete Container Images from GCR ───
echo ""
echo "--- Step 2: Removing Container Images ---"
if [ -n "$PROJECT_ID" ]; then
    gcloud container images delete "gcr.io/${PROJECT_ID}/vuln-app:latest" --quiet --force-delete-tags 2>/dev/null || echo "  vuln-app image not found or already deleted"
    gcloud container images delete "gcr.io/${PROJECT_ID}/vuln-ai-service:latest" --quiet --force-delete-tags 2>/dev/null || echo "  vuln-ai-service image not found or already deleted"
    echo "GCR images removed."
else
    echo "Could not determine project ID, skipping GCR cleanup."
fi

# ─── Step 3: Terraform Destroy ───
echo ""
echo "--- Step 3: Terraform Destroy ---"
cd "$PROJECT_ROOT/terraform"

if [ -f terraform.tfstate ] || [ -d .terraform ]; then
    terraform destroy -auto-approve
    echo "Infrastructure destroyed."
else
    echo "No Terraform state found, skipping."
fi

# ─── Step 4: Clean Local Files ───
echo ""
echo "--- Step 4: Cleaning Local State ---"
rm -f "$PROJECT_ROOT/terraform/tfplan"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate"
rm -f "$PROJECT_ROOT/terraform/terraform.tfstate.backup"
rm -rf "$PROJECT_ROOT/terraform/.terraform"
rm -f "$PROJECT_ROOT/terraform/.terraform.lock.hcl"
rm -f "$PROJECT_ROOT/app/governance.db"
echo "Local state cleaned."

echo ""
echo "============================================="
echo "  Cleanup Complete!"
echo "============================================="
echo "  All lab resources have been destroyed."
echo "  To redeploy: ./scripts/setup.sh && ./scripts/deploy.sh"
echo "============================================="
