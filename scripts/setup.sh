#!/bin/bash
# =============================================================================
# 5C Security Lab - Initial Setup Script
# Checks prerequisites, enables GCP APIs, initializes Terraform
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================="
echo "  5C Security Lab - Initial Setup"
echo "============================================="
echo ""

# Check prerequisites
echo "--- Checking prerequisites ---"
MISSING=0

for cmd in gcloud terraform kubectl docker; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "[OK] $cmd found: $(command -v "$cmd")"
    else
        echo "[MISSING] $cmd is required but not installed"
        MISSING=1
    fi
done

if [ "$MISSING" -eq 1 ]; then
    echo ""
    echo "ERROR: Missing required tools. Please install them and re-run."
    exit 1
fi

echo ""

# Get or prompt for project ID
PROJECT_ID="${GCP_PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
    echo "Enter your GCP Project ID:"
    read -r PROJECT_ID
fi

if [ -z "$PROJECT_ID" ]; then
    echo "ERROR: GCP Project ID is required"
    exit 1
fi

echo "Using project: $PROJECT_ID"
echo ""

# Set gcloud project
echo "--- Configuring gcloud ---"
gcloud config set project "$PROJECT_ID"

# Authenticate if needed
if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 | grep -q "@"; then
    echo "No active gcloud auth found. Please authenticate:"
    gcloud auth login
fi

# Enable required GCP APIs
echo ""
echo "--- Enabling GCP APIs ---"
gcloud services enable \
    compute.googleapis.com \
    container.googleapis.com \
    storage.googleapis.com \
    iam.googleapis.com \
    aiplatform.googleapis.com \
    containerregistry.googleapis.com \
    cloudresourcemanager.googleapis.com \
    --project="$PROJECT_ID"
echo "APIs enabled successfully."

# Configure Docker for GCR
echo ""
echo "--- Configuring Docker for GCR ---"
gcloud auth configure-docker gcr.io --quiet
echo "Docker configured for gcr.io"

# Initialize Terraform
echo ""
echo "--- Initializing Terraform ---"
cd "$PROJECT_ROOT/terraform"

if [ ! -f terraform.tfvars ]; then
    echo "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
    sed -i "s/YOUR_GCP_PROJECT_ID/$PROJECT_ID/" terraform.tfvars
    echo "terraform.tfvars created with project_id=$PROJECT_ID"
else
    echo "terraform.tfvars already exists, skipping creation"
fi

terraform init

echo ""
echo "--- Running Terraform Plan ---"
terraform plan -out=tfplan

echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
echo "Review the Terraform plan above."
echo "When ready, run: ./scripts/deploy.sh"
echo ""
