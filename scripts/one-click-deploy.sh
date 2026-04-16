#!/bin/bash
# =============================================================================
# 5C Security Lab - One-Click Deployment Script
#
# Does EVERYTHING from scratch:
#   1. Checks prerequisites (gcloud, terraform, kubectl, docker)
#   2. Verifies gcloud auth + ADC (Application Default Credentials)
#   3. Verifies project, billing, and APIs
#   4. Configures Docker for GCR
#   5. Creates/updates terraform.tfvars
#   6. Runs terraform init + plan + apply
#   7. Builds and pushes Docker images to GCR
#   8. Gets GKE credentials
#   9. Substitutes placeholders and applies Kubernetes manifests
#   10. Waits for pods to be ready
#   11. Prints access URL and next steps
#
# Usage:
#   export PROJECT_ID="your-project-id"              # required
#   export BILLING_ACCOUNT="XXXXXX-XXXXXX-XXXXXX"    # optional (only needed for new projects)
#   ./scripts/one-click-deploy.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

section() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

# -----------------------------------------------------------------------------
# Step 0: Safety Checks — do not run as root
# -----------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    fail "Do NOT run this script with sudo or as root. Run as your regular user.
    Reason: gcloud/docker credentials are per-user. Running as root bypasses
    your existing authentication and can't access the Google OAuth flow."
fi

# -----------------------------------------------------------------------------
# Step 1: Prerequisite Check
# -----------------------------------------------------------------------------
section "Step 1/11: Checking Prerequisites"

MISSING=0
for cmd in gcloud terraform kubectl docker; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd found"
    else
        warn "$cmd is MISSING"
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] || fail "Install missing prerequisites and re-run"

# Detect if we have a browser/display available
HEADLESS=0
if [ -z "${DISPLAY:-}" ] || ! command -v xdg-open >/dev/null 2>&1 || \
   ! (command -v firefox >/dev/null 2>&1 || command -v chromium >/dev/null 2>&1 || \
      command -v google-chrome >/dev/null 2>&1 || command -v chromium-browser >/dev/null 2>&1); then
    HEADLESS=1
    warn "No browser detected — using headless OAuth flow (--no-launch-browser)"
fi

# -----------------------------------------------------------------------------
# Step 2: Verify gcloud Authentication
# -----------------------------------------------------------------------------
section "Step 2/11: Verifying gcloud Authentication"

if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | grep -q "@"; then
    warn "No active gcloud session found"
    if [ "$HEADLESS" -eq 1 ]; then
        log "Running headless: gcloud auth login --no-launch-browser"
        log "You'll get a URL — open it on ANY machine with a browser, paste the code back here."
        gcloud auth login --no-launch-browser
    else
        log "Running: gcloud auth login"
        gcloud auth login
    fi
fi
ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1)
ok "Active account: $ACTIVE_ACCOUNT"

# -----------------------------------------------------------------------------
# Step 3: Verify Application Default Credentials (ADC) for Terraform
# -----------------------------------------------------------------------------
section "Step 3/11: Verifying Application Default Credentials"

ADC_PATH="$HOME/.config/gcloud/application_default_credentials.json"
if [ ! -f "$ADC_PATH" ]; then
    warn "ADC not configured. Terraform needs this."
    if [ "$HEADLESS" -eq 1 ]; then
        log "Running headless: gcloud auth application-default login --no-launch-browser"
        gcloud auth application-default login --no-launch-browser
    else
        log "Running: gcloud auth application-default login"
        gcloud auth application-default login
    fi
fi

if gcloud auth application-default print-access-token >/dev/null 2>&1; then
    ok "ADC is configured and valid"
else
    fail "ADC token cannot be obtained. Run: gcloud auth application-default login"
fi

# -----------------------------------------------------------------------------
# Step 4: Resolve PROJECT_ID
# -----------------------------------------------------------------------------
section "Step 4/11: Resolving GCP Project"

PROJECT_ID="${PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "(unset)" ]; then
        echo "PROJECT_ID not set. Enter your GCP project ID (must start with a letter):"
        read -r PROJECT_ID
    fi
fi

# Validate project ID format
if ! [[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{5,29}$ ]]; then
    fail "Invalid project ID '$PROJECT_ID'. Must start with lowercase letter, 6-30 chars (letters/digits/hyphens)."
fi

log "Using project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID" >/dev/null

# Verify project exists and user has access
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    warn "Project $PROJECT_ID not found. Creating..."
    gcloud projects create "$PROJECT_ID" --name="5C Security Lab"
    ok "Project $PROJECT_ID created"
fi
ok "Project $PROJECT_ID is accessible"

# -----------------------------------------------------------------------------
# Step 5: Verify Billing Is Linked
# -----------------------------------------------------------------------------
section "Step 5/11: Verifying Billing"

BILLING_ENABLED=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "False")
if [ "$BILLING_ENABLED" != "True" ]; then
    warn "Billing is NOT enabled on project $PROJECT_ID"
    BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"
    if [ -z "$BILLING_ACCOUNT" ]; then
        echo "Your available billing accounts:"
        gcloud billing accounts list --format="table(ACCOUNT_ID, NAME, OPEN)"
        echo "Enter your BILLING_ACCOUNT_ID (format: XXXXXX-XXXXXX-XXXXXX):"
        read -r BILLING_ACCOUNT
    fi
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
    ok "Billing linked"
else
    ok "Billing is enabled"
fi

# -----------------------------------------------------------------------------
# Step 6: Enable Required APIs
# -----------------------------------------------------------------------------
section "Step 6/11: Enabling Required APIs"

REQUIRED_APIS=(
    "compute.googleapis.com"
    "container.googleapis.com"
    "storage.googleapis.com"
    "iam.googleapis.com"
    "aiplatform.googleapis.com"
    "containerregistry.googleapis.com"
    "cloudresourcemanager.googleapis.com"
)

log "Enabling ${#REQUIRED_APIS[@]} APIs (this may take 1-2 minutes)..."
gcloud services enable "${REQUIRED_APIS[@]}" --project="$PROJECT_ID"
ok "All APIs enabled"

# -----------------------------------------------------------------------------
# Step 7: Configure Docker for GCR
# -----------------------------------------------------------------------------
section "Step 7/11: Configuring Docker for GCR"

gcloud auth configure-docker gcr.io --quiet >/dev/null 2>&1
ok "Docker configured for gcr.io"

# -----------------------------------------------------------------------------
# Step 8: Terraform Init + Apply
# -----------------------------------------------------------------------------
section "Step 8/11: Deploying Infrastructure with Terraform"

cd "$PROJECT_ROOT/terraform"

# Create tfvars if missing
if [ ! -f terraform.tfvars ]; then
    log "Creating terraform.tfvars from example..."
    cp terraform.tfvars.example terraform.tfvars
fi
# Always enforce correct project_id (idempotent)
sed -i "s/^project_id.*/project_id = \"$PROJECT_ID\"/" terraform.tfvars

log "Running terraform init..."
terraform init -upgrade >/dev/null 2>&1 || terraform init -upgrade
ok "Terraform initialized"

log "Running terraform validate..."
terraform validate
ok "Terraform config valid"

log "Running terraform plan (this takes ~30s)..."
rm -f tfplan
terraform plan -out=tfplan
ok "Plan generated"

log "Running terraform apply (this takes 8-12 minutes)..."
log "GKE cluster creation is the bottleneck. Grab a coffee."
terraform apply tfplan
ok "Infrastructure deployed"

# Capture outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)
BUCKET_NAME=$(terraform output -raw bucket_name)
REGION=$(terraform output -raw region)
ZONE="${REGION}-a"

log "Cluster: $CLUSTER_NAME"
log "Bucket:  gs://$BUCKET_NAME"
log "Region:  $REGION"

# -----------------------------------------------------------------------------
# Step 9: Build and Push Docker Images
# -----------------------------------------------------------------------------
section "Step 9/11: Building and Pushing Docker Images"

cd "$PROJECT_ROOT"

APP_IMAGE="gcr.io/${PROJECT_ID}/vuln-app:latest"
AI_IMAGE="gcr.io/${PROJECT_ID}/vuln-ai-service:latest"

log "Building $APP_IMAGE..."
docker build -f docker/Dockerfile.app -t "$APP_IMAGE" . 2>&1 | tail -5
ok "App image built"

log "Building $AI_IMAGE..."
docker build -f docker/Dockerfile.ai -t "$AI_IMAGE" . 2>&1 | tail -5
ok "AI image built"

log "Pushing $APP_IMAGE..."
docker push "$APP_IMAGE" 2>&1 | tail -3

log "Pushing $AI_IMAGE..."
docker push "$AI_IMAGE" 2>&1 | tail -3

ok "Both images pushed to GCR"

# -----------------------------------------------------------------------------
# Step 10: Deploy to GKE
# -----------------------------------------------------------------------------
section "Step 10/11: Deploying to GKE"

log "Getting cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"
ok "kubectl configured for $CLUSTER_NAME"

log "Verifying cluster connection..."
kubectl get nodes --no-headers | head -5
ok "Cluster is reachable"

cd "$PROJECT_ROOT/kubernetes"

# Create temp dir with substituted manifests
TEMP_DIR=$(mktemp -d)
cp ./*.yaml "$TEMP_DIR/"

log "Substituting placeholders in manifests..."
sed -i "s|REPLACE_APP_IMAGE|${APP_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_AI_IMAGE|${AI_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_BUCKET_NAME|${BUCKET_NAME}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_PROJECT_ID|${PROJECT_ID}|g" "$TEMP_DIR"/*.yaml

log "Applying manifests in dependency order..."
kubectl apply -f "$TEMP_DIR/namespaces.yaml"
kubectl apply -f "$TEMP_DIR/serviceaccount.yaml"
kubectl apply -f "$TEMP_DIR/rbac.yaml"
kubectl apply -f "$TEMP_DIR/app-deployment.yaml"
kubectl apply -f "$TEMP_DIR/app-service.yaml"
kubectl apply -f "$TEMP_DIR/ai-deployment.yaml"
kubectl apply -f "$TEMP_DIR/ai-service.yaml"

rm -rf "$TEMP_DIR"
ok "Manifests applied"

log "Waiting for pods to become ready (up to 3 minutes)..."
kubectl -n ai-governance wait --for=condition=ready pod -l app=vuln-app --timeout=180s || warn "vuln-app pod not ready after 180s"
kubectl -n ai-governance wait --for=condition=ready pod -l app=ai-service --timeout=180s || warn "ai-service pod not ready after 180s"

# -----------------------------------------------------------------------------
# Step 11: Verify and Print Access Info
# -----------------------------------------------------------------------------
section "Step 11/11: Verifying Deployment"

log "Pod status:"
kubectl get pods -n ai-governance

echo ""
log "Service status:"
kubectl get svc -n ai-governance

echo ""
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    warn "No external IP. Use port-forward: kubectl port-forward -n ai-governance svc/vuln-app 8080:8080"
fi

log "Smoke-testing the app..."
if curl -s -o /dev/null -w "%{http_code}" "http://${NODE_IP}:30080/health?check=basic" --max-time 10 | grep -q "200"; then
    ok "Application is responding on port 30080"
else
    warn "App did not respond within 10s. Check firewall rules and pod logs."
fi

echo ""
section "DEPLOYMENT COMPLETE"
echo ""
echo -e "  ${GREEN}App URL:${NC}     http://${NODE_IP}:30080"
echo -e "  ${GREEN}GCS Bucket:${NC}  gs://${BUCKET_NAME}"
echo -e "  ${GREEN}Cluster:${NC}     ${CLUSTER_NAME}"
echo -e "  ${GREEN}Project:${NC}     ${PROJECT_ID}"
echo ""
echo "  Save this for labs:"
echo "    export NODE_IP=${NODE_IP}"
echo "    export PROJECT_ID=${PROJECT_ID}"
echo ""
echo "  Start labs: open labs/lab01-code-injection.md"
echo "  Cost: ~\$5-10/day. Run ./scripts/one-click-teardown.sh after labs."
echo ""
