#!/bin/bash
# =============================================================================
# 5C Security Lab - Kubernetes-Only Deploy Script (Linux)
#
# Deploys the vulnerable app and AI service to an existing GKE cluster.
# Assumes:
#   - Terraform infrastructure is already deployed (GKE cluster exists)
#   - Both Docker images are already in GCR (via Cloud Build or local push)
#   - gcloud is authenticated and project is set
#
# Usage:
#   export PROJECT_ID="lab-5csec-317009"        # optional - auto-detected
#   ./scripts/deploy-k8s.sh
#
# Environment overrides:
#   PROJECT_ID   - GCP project ID (default: from terraform or gcloud config)
#   ZONE         - GKE cluster zone (default: us-central1-a)
#   CLUSTER_NAME - GKE cluster name (default: vuln-gke-cluster)
#   BUCKET_NAME  - GCS bucket name (default: from terraform output)
# =============================================================================

set -euo pipefail

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
fail()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

section() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

# -----------------------------------------------------------------------------
# Safety: do not run as root
# -----------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    fail "Do NOT run this script as root. Run as your regular user.
    Kubernetes credentials are stored per-user under ~/.kube/config."
fi

# -----------------------------------------------------------------------------
# Step 1: Prerequisite Check
# -----------------------------------------------------------------------------
section "Step 1/6: Checking Prerequisites"

MISSING=0
for cmd in gcloud kubectl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd found"
    else
        warn "$cmd is MISSING"
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] || fail "Install missing prerequisites. For kubectl: gcloud components install kubectl"

# -----------------------------------------------------------------------------
# Step 2: Resolve Configuration (PROJECT_ID, ZONE, CLUSTER_NAME, BUCKET_NAME)
# -----------------------------------------------------------------------------
section "Step 2/6: Resolving Configuration"

# PROJECT_ID: env var > terraform output > gcloud config
PROJECT_ID="${PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
    if [ -d "$PROJECT_ROOT/terraform/.terraform" ]; then
        PROJECT_ID=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw project_id 2>/dev/null || echo "")
    fi
fi
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi
[ -n "$PROJECT_ID" ] || fail "Cannot determine PROJECT_ID. Set it: export PROJECT_ID=your-project-id"

# ZONE: env var > default
ZONE="${ZONE:-us-central1-a}"

# CLUSTER_NAME: env var > default
CLUSTER_NAME="${CLUSTER_NAME:-vuln-gke-cluster}"

# BUCKET_NAME: env var > terraform output > computed default
BUCKET_NAME="${BUCKET_NAME:-}"
if [ -z "$BUCKET_NAME" ] && [ -d "$PROJECT_ROOT/terraform/.terraform" ]; then
    BUCKET_NAME=$(cd "$PROJECT_ROOT/terraform" && terraform output -raw bucket_name 2>/dev/null || echo "")
fi
if [ -z "$BUCKET_NAME" ]; then
    BUCKET_NAME="vuln-ai-governance-data-${PROJECT_ID}"
fi

APP_IMAGE="gcr.io/${PROJECT_ID}/vuln-app:latest"
AI_IMAGE="gcr.io/${PROJECT_ID}/vuln-ai-service:latest"

log "Project:     $PROJECT_ID"
log "Zone:        $ZONE"
log "Cluster:     $CLUSTER_NAME"
log "Bucket:      $BUCKET_NAME"
log "App image:   $APP_IMAGE"
log "AI image:    $AI_IMAGE"

# -----------------------------------------------------------------------------
# Step 3: Verify Cluster Exists and Images Are Available
# -----------------------------------------------------------------------------
section "Step 3/6: Verifying Preconditions"

if ! gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" >/dev/null 2>&1; then
    fail "GKE cluster '$CLUSTER_NAME' not found in $ZONE.
    Run terraform apply first: cd terraform && terraform apply"
fi
ok "GKE cluster '$CLUSTER_NAME' exists"

for image in vuln-app vuln-ai-service; do
    if ! gcloud container images describe "gcr.io/${PROJECT_ID}/${image}:latest" >/dev/null 2>&1; then
        fail "Image gcr.io/${PROJECT_ID}/${image}:latest not found in GCR.
    Build and push via: gcloud builds submit --config cloudbuild.yaml ."
    fi
    ok "Image $image exists in GCR"
done

# -----------------------------------------------------------------------------
# Step 4: Configure kubectl
# -----------------------------------------------------------------------------
section "Step 4/6: Configuring kubectl"

log "Fetching cluster credentials..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" --project "$PROJECT_ID"

if ! kubectl cluster-info >/dev/null 2>&1; then
    fail "kubectl cannot connect to the cluster"
fi
ok "kubectl connected to $CLUSTER_NAME"

log "Cluster nodes:"
kubectl get nodes --no-headers | awk '{print "  "$1" - "$2}'

# -----------------------------------------------------------------------------
# Step 5: Apply Kubernetes Manifests
# -----------------------------------------------------------------------------
section "Step 5/6: Deploying to Kubernetes"

cd "$PROJECT_ROOT/kubernetes"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log "Substituting placeholders..."
cp ./*.yaml "$TEMP_DIR/"
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

ok "Manifests applied"

log "Waiting for pods to become ready (up to 3 min)..."
if kubectl -n ai-governance wait --for=condition=ready pod -l app=vuln-app --timeout=180s 2>/dev/null; then
    ok "vuln-app pod ready"
else
    warn "vuln-app pod not ready after 180s"
    kubectl -n ai-governance describe pod -l app=vuln-app | tail -30
fi

if kubectl -n ai-governance wait --for=condition=ready pod -l app=ai-service --timeout=180s 2>/dev/null; then
    ok "ai-service pod ready"
else
    warn "ai-service pod not ready after 180s"
    kubectl -n ai-governance describe pod -l app=ai-service | tail -30
fi

# -----------------------------------------------------------------------------
# Step 6: Verify Deployment and Get Access URL
# -----------------------------------------------------------------------------
section "Step 6/6: Verifying Deployment"

echo ""
log "Pod status:"
kubectl get pods -n ai-governance -o wide

echo ""
log "Service status:"
kubectl get svc -n ai-governance

echo ""
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    warn "No external node IP found. Using internal IP. For external access, use:"
    warn "  kubectl port-forward -n ai-governance svc/vuln-app 8080:8080"
fi

log "Smoke-testing the app..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "http://${NODE_IP}:30080/health?check=basic" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
    ok "App responding on port 30080 (HTTP $HTTP_STATUS)"
else
    warn "App did not respond within 10s (HTTP $HTTP_STATUS)"
    warn "  Check firewall: gcloud compute firewall-rules list --filter=\"name~nodeports\""
    warn "  Check pod logs: kubectl logs -n ai-governance -l app=vuln-app"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETE${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "  ${GREEN}App URL:${NC}     http://${NODE_IP}:30080"
echo -e "  ${GREEN}GCS Bucket:${NC}  gs://${BUCKET_NAME}"
echo -e "  ${GREEN}Cluster:${NC}     ${CLUSTER_NAME}"
echo -e "  ${GREEN}Project:${NC}     ${PROJECT_ID}"
echo ""
echo "  Save for labs:"
echo "    export NODE_IP=${NODE_IP}"
echo "    export PROJECT_ID=${PROJECT_ID}"
echo ""
echo "  Start with Lab 01: cat labs/lab01-code-injection.md"
echo "  Teardown later:    ./scripts/one-click-teardown.sh"
echo ""
