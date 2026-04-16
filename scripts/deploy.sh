#!/bin/bash
# =============================================================================
# 5C Security Lab - Full Deployment Script
# Terraform apply -> Docker build/push -> Kubernetes deploy
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================="
echo "  5C Security Lab - Full Deployment"
echo "============================================="
echo ""

# ─── Step 1: Terraform Apply ───
echo "--- Step 1: Terraform Apply ---"
cd "$PROJECT_ROOT/terraform"

# Get project ID from tfvars
PROJECT_ID=$(grep 'project_id' terraform.tfvars | head -1 | cut -d'"' -f2)
if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "YOUR_GCP_PROJECT_ID" ]; then
    echo "ERROR: Set your project_id in terraform/terraform.tfvars first"
    echo "       Run ./scripts/setup.sh to configure"
    exit 1
fi

echo "Project: $PROJECT_ID"

terraform apply -auto-approve

# Capture outputs
CLUSTER_NAME=$(terraform output -raw cluster_name)
BUCKET_NAME=$(terraform output -raw bucket_name)
REGION=$(terraform output -raw region)
ZONE="${REGION}-a"

echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Bucket:  $BUCKET_NAME"
echo "Region:  $REGION"

# ─── Step 2: Build and Push Docker Images ───
echo ""
echo "--- Step 2: Build and Push Docker Images ---"
cd "$PROJECT_ROOT"

APP_IMAGE="gcr.io/${PROJECT_ID}/vuln-app:latest"
AI_IMAGE="gcr.io/${PROJECT_ID}/vuln-ai-service:latest"

echo "Building app image: $APP_IMAGE"
docker build -f docker/Dockerfile.app -t "$APP_IMAGE" .

echo "Building AI image: $AI_IMAGE"
docker build -f docker/Dockerfile.ai -t "$AI_IMAGE" .

echo "Pushing images to GCR..."
docker push "$APP_IMAGE"
docker push "$AI_IMAGE"

echo "Images pushed successfully."

# ─── Step 3: Configure kubectl ───
echo ""
echo "--- Step 3: Configure kubectl ---"
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID"

echo "kubectl configured for cluster: $CLUSTER_NAME"

# ─── Step 4: Deploy Kubernetes Resources ───
echo ""
echo "--- Step 4: Deploy to GKE ---"
cd "$PROJECT_ROOT/kubernetes"

# Create temp dir for substituted manifests
TEMP_DIR=$(mktemp -d)
cp ./*.yaml "$TEMP_DIR/"

# Substitute placeholders
sed -i "s|REPLACE_APP_IMAGE|${APP_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_AI_IMAGE|${AI_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_BUCKET_NAME|${BUCKET_NAME}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_PROJECT_ID|${PROJECT_ID}|g" "$TEMP_DIR"/*.yaml

# Apply in dependency order
echo "Creating namespaces..."
kubectl apply -f "$TEMP_DIR/namespaces.yaml"

echo "Creating service accounts..."
kubectl apply -f "$TEMP_DIR/serviceaccount.yaml"

echo "Creating RBAC..."
kubectl apply -f "$TEMP_DIR/rbac.yaml"

echo "Deploying application..."
kubectl apply -f "$TEMP_DIR/app-deployment.yaml"
kubectl apply -f "$TEMP_DIR/app-service.yaml"

echo "Deploying AI service..."
kubectl apply -f "$TEMP_DIR/ai-deployment.yaml"
kubectl apply -f "$TEMP_DIR/ai-service.yaml"

# Cleanup temp
rm -rf "$TEMP_DIR"

# ─── Step 5: Wait for Pods ───
echo ""
echo "--- Step 5: Waiting for pods to be ready ---"
kubectl -n ai-governance wait --for=condition=ready pod -l app=vuln-app --timeout=180s || echo "WARNING: App pod not ready after 180s"
kubectl -n ai-governance wait --for=condition=ready pod -l app=ai-service --timeout=180s || echo "WARNING: AI pod not ready after 180s"

# ─── Step 6: Display Access Info ───
echo ""
echo "--- Deployment Status ---"
kubectl get pods -n ai-governance
kubectl get services -n ai-governance
echo ""

# Get node external IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "NOTE: No external IP found. Using internal IP (use port-forward for access)."
fi

echo "============================================="
echo "  Deployment Complete!"
echo "============================================="
echo ""
echo "  App URL:     http://${NODE_IP}:30080"
echo "  GCS Bucket:  gs://${BUCKET_NAME}"
echo "  Cluster:     ${CLUSTER_NAME}"
echo "  Project:     ${PROJECT_ID}"
echo ""
echo "  Start with Lab 01: labs/lab01-code-injection.md"
echo ""
echo "  To clean up: ./scripts/cleanup.sh"
echo "============================================="
