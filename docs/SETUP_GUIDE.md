# 5C Security Lab - Detailed GCP Deployment Guide

> **Estimated deployment time**: 20-30 minutes
> **Estimated cost**: ~$5-10/day (run cleanup immediately after labs)

---

## Phase 0: Prerequisites Installation

### 0.1 Install Google Cloud SDK

```bash
# Linux/macOS
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud version
```

For Windows: Download the installer from https://cloud.google.com/sdk/docs/install

### 0.2 Install Terraform

```bash
# Linux (AMD64)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Verify
terraform version
# Expected: Terraform v1.5.0 or higher
```

### 0.3 Install kubectl

```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Verify
kubectl version --client
# Expected: v1.28+ or higher
```

### 0.4 Install Docker

```bash
# Linux (Ubuntu/Debian)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# macOS
# Install Docker Desktop from https://www.docker.com/products/docker-desktop/

# Verify
docker version
# Expected: Docker version 24+ or higher
```

### 0.5 Verify All Prerequisites

```bash
echo "=== Prerequisite Check ==="
gcloud version --format="value(Google Cloud SDK)" 2>/dev/null && echo "gcloud: OK" || echo "gcloud: MISSING"
terraform version -json 2>/dev/null | head -1 && echo "terraform: OK" || echo "terraform: MISSING"
kubectl version --client --short 2>/dev/null && echo "kubectl: OK" || echo "kubectl: MISSING"
docker version --format '{{.Server.Version}}' 2>/dev/null && echo "docker: OK" || echo "docker: MISSING"
```

---

## Phase 1: GCP Project Setup

### 1.1 Authenticate with Google Cloud

```bash
# Interactive login (opens browser)
gcloud auth login

# Set Application Default Credentials (required by Terraform)
gcloud auth application-default login
```

### 1.2 Create a New GCP Project (Recommended)

Using a dedicated project isolates lab resources and makes cleanup simple.

```bash
# Choose a unique project ID (must be globally unique)
# IMPORTANT: Must start with a LOWERCASE LETTER (not a digit)
# Must be 6-30 characters, lowercase letters/digits/hyphens only
export PROJECT_ID="lab-5csec-$(date +%s | tail -c 7)"
echo "Project ID: $PROJECT_ID"

# Create the project
gcloud projects create $PROJECT_ID --name="5C Security Lab"

# Verify the project was actually created before proceeding
gcloud projects describe $PROJECT_ID || { echo "Project creation failed. Check quota or permissions."; exit 1; }

# Set as active project
gcloud config set project $PROJECT_ID
```

> **Note**: GCP project IDs cannot start with a digit. If you see `Bad value [...]: ...must start with a lowercase letter`, adjust the prefix. Personal Gmail accounts are limited to ~10-12 projects lifetime — run `gcloud projects list` to check your count.

Or use an existing project:

```bash
export PROJECT_ID="your-existing-project-id"
gcloud config set project $PROJECT_ID
```

### 1.3 Link a Billing Account

GKE, GCS, and Vertex AI require an active billing account.

```bash
# List your billing accounts - COPY THE ACCOUNT_ID FROM THIS OUTPUT
gcloud billing accounts list
```

Example output:
```text
ACCOUNT_ID            NAME                OPEN  MASTER_ACCOUNT_ID
01ABCD-123456-EFGH99  My Billing Account  True
```

```bash
# Link billing using the ACCOUNT_ID from above (NOT the literal string)
export BILLING_ACCOUNT="01ABCD-123456-EFGH99"    # Replace with yours
gcloud billing projects link $PROJECT_ID \
  --billing-account=$BILLING_ACCOUNT
```

If you don't have a billing account, create one at https://console.cloud.google.com/billing

### 1.4 Enable Required GCP APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  aiplatform.googleapis.com \
  containerregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=$PROJECT_ID

echo "All APIs enabled."
```

### 1.5 Check Regional CPU Quota

GKE needs 2x e2-standard-4 (8 vCPUs total). Verify your quota:

```bash
gcloud compute regions describe us-central1 \
  --project=$PROJECT_ID \
  --format="table(quotas.filter(metric='CPUS').limit, quotas.filter(metric='CPUS').usage)"
```

If the limit is below 8, request a quota increase at:
https://console.cloud.google.com/iam-admin/quotas?project=YOUR_PROJECT_ID

### 1.6 Configure Docker for Google Container Registry

```bash
gcloud auth configure-docker gcr.io --quiet
echo "Docker configured for gcr.io push/pull."
```

---

## Phase 2: Clone and Configure the Repository

### 2.1 Clone the Repository

```bash
git clone https://github.com/writetozealdefense-svg/5Clabdemo-code.git
cd 5Clabdemo-code
```

### 2.2 Make Scripts Executable

```bash
chmod +x scripts/*.sh
```

### 2.3 Create Terraform Variables File

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Set your project ID
sed -i "s/YOUR_GCP_PROJECT_ID/$PROJECT_ID/" terraform.tfvars

# Verify
cat terraform.tfvars
# Should show: project_id = "your-actual-project-id"
```

### 2.4 Review Default Configuration

The defaults in `variables.tf` are:

| Variable | Default | Description |
|----------|---------|-------------|
| `region` | us-central1 | GCP region |
| `zone` | us-central1-a | GKE cluster zone |
| `cluster_name` | vuln-gke-cluster | GKE cluster name |
| `machine_type` | e2-standard-4 | Node machine type |
| `node_count` | 2 | Number of GKE nodes |

To override any default, add it to `terraform.tfvars`:

```bash
# Example: use a cheaper machine type for cost savings
echo 'machine_type = "e2-standard-2"' >> terraform.tfvars
```

---

## Phase 3: Deploy Infrastructure with Terraform

### 3.1 Initialize Terraform

```bash
# Still in the terraform/ directory
terraform init
```

Expected output:
```text
Initializing the backend...
Initializing provider plugins...
- Installing hashicorp/google v5.x.x...
- Installing hashicorp/google-beta v5.x.x...
Terraform has been successfully initialized!
```

### 3.2 Preview the Infrastructure Plan

```bash
terraform plan -out=tfplan
```

Review the plan output. You should see approximately:
```text
Plan: 14 to add, 0 to change, 0 to destroy.

Resources to be created:
  - google_compute_network.vuln_network
  - google_compute_subnetwork.vuln_subnet
  - google_compute_firewall.allow_all_internal
  - google_compute_firewall.allow_ssh_from_anywhere
  - google_compute_firewall.allow_nodeports
  - google_compute_firewall.allow_management
  - google_service_account.gke_node_sa
  - google_project_iam_member.node_sa_editor
  - google_project_iam_member.node_sa_storage_admin
  - google_project_iam_member.node_sa_aiplatform_admin
  - google_service_account_key.node_sa_key
  - google_container_cluster.vuln_cluster
  - google_container_node_pool.vuln_nodes
  - google_storage_bucket.vuln_data_bucket
  - google_storage_bucket_iam_member.public_read
  - google_storage_bucket_object.pii_data
  - google_storage_bucket_object.knowledge_base
  - google_project_service.* (API enablements)
```

### 3.3 Apply the Infrastructure

```bash
terraform apply tfplan
```

This takes **8-12 minutes** (GKE cluster creation is the bottleneck).

Expected final output:
```text
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

Outputs:
bucket_name = "vuln-ai-governance-data-your-project-id"
bucket_url = "gs://vuln-ai-governance-data-your-project-id"
cluster_name = "vuln-gke-cluster"
gke_connect_command = "gcloud container clusters get-credentials vuln-gke-cluster --zone us-central1-a --project your-project-id"
node_sa_email = "vuln-gke-node-sa@your-project-id.iam.gserviceaccount.com"
project_id = "your-project-id"
region = "us-central1"
```

### 3.4 Verify Infrastructure

```bash
# Verify GKE cluster
gcloud container clusters list --project=$PROJECT_ID
# Expected: vuln-gke-cluster in us-central1-a, RUNNING

# Verify GCS bucket
gsutil ls gs://vuln-ai-governance-data-$PROJECT_ID/
# Expected: data/sample_pii.json, data/knowledge_base/

# Verify service account
gcloud iam service-accounts list --project=$PROJECT_ID --filter="email~vuln-gke-node-sa"
# Expected: vuln-gke-node-sa@...

# Verify firewall rules
gcloud compute firewall-rules list --project=$PROJECT_ID --filter="name~vuln"
# Expected: 4 firewall rules
```

---

## Phase 4: Build and Push Docker Images

### 4.1 Build the Application Image

```bash
# Return to project root
cd ..

# Build the vulnerable Flask app image
docker build -f docker/Dockerfile.app -t gcr.io/$PROJECT_ID/vuln-app:latest .
```

Expected output (last lines):
```text
Successfully built abc123def456
Successfully tagged gcr.io/your-project-id/vuln-app:latest
```

### 4.2 Build the AI Service Image

```bash
docker build -f docker/Dockerfile.ai -t gcr.io/$PROJECT_ID/vuln-ai-service:latest .
```

### 4.3 Push Both Images to Google Container Registry

```bash
docker push gcr.io/$PROJECT_ID/vuln-app:latest
docker push gcr.io/$PROJECT_ID/vuln-ai-service:latest
```

### 4.4 Verify Images in GCR

```bash
gcloud container images list --repository=gcr.io/$PROJECT_ID
```

Expected output:
```text
NAME
gcr.io/your-project-id/vuln-app
gcr.io/your-project-id/vuln-ai-service
```

---

## Phase 5: Configure kubectl and Deploy to GKE

### 5.1 Get GKE Cluster Credentials

```bash
gcloud container clusters get-credentials vuln-gke-cluster \
  --zone us-central1-a \
  --project $PROJECT_ID
```

Expected output:
```text
Fetching cluster endpoint and auth data.
kubeconfig entry generated for vuln-gke-cluster.
```

### 5.2 Verify kubectl Connection

```bash
kubectl cluster-info
kubectl get nodes
```

Expected:
```text
NAME                                                STATUS   ROLES    AGE   VERSION
gke-vuln-gke-cluster-vuln-gke-cluste-xxxxxxxx-xxxx  Ready    <none>   5m    v1.28.x
gke-vuln-gke-cluster-vuln-gke-cluste-xxxxxxxx-xxxx  Ready    <none>   5m    v1.28.x
```

### 5.3 Prepare Kubernetes Manifests

The YAML files contain placeholders (`REPLACE_APP_IMAGE`, etc.) that must be substituted with actual values before applying.

```bash
cd kubernetes

# Capture terraform outputs
BUCKET_NAME=$(cd ../terraform && terraform output -raw bucket_name)
APP_IMAGE="gcr.io/${PROJECT_ID}/vuln-app:latest"
AI_IMAGE="gcr.io/${PROJECT_ID}/vuln-ai-service:latest"

# Create a temporary directory with substituted manifests
TEMP_DIR=$(mktemp -d)
cp *.yaml "$TEMP_DIR/"

sed -i "s|REPLACE_APP_IMAGE|${APP_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_AI_IMAGE|${AI_IMAGE}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_BUCKET_NAME|${BUCKET_NAME}|g" "$TEMP_DIR"/*.yaml
sed -i "s|REPLACE_PROJECT_ID|${PROJECT_ID}|g" "$TEMP_DIR"/*.yaml

echo "Manifests prepared in $TEMP_DIR"
```

### 5.4 Apply Kubernetes Resources (In Order)

Resources must be applied in dependency order:

```bash
# Step 1: Create namespaces
kubectl apply -f "$TEMP_DIR/namespaces.yaml"
# Expected: namespace/ai-governance created
#           namespace/finance-prod created

# Step 2: Create service accounts
kubectl apply -f "$TEMP_DIR/serviceaccount.yaml"
# Expected: serviceaccount/vuln-app-sa created (x2)

# Step 3: Create RBAC (over-permissive cluster roles)
kubectl apply -f "$TEMP_DIR/rbac.yaml"
# Expected: clusterrole/vuln-cluster-admin created
#           clusterrolebinding/vuln-app-cluster-admin created
#           clusterrolebinding/vuln-app-cluster-admin-prod created

# Step 4: Deploy the vulnerable Flask application
kubectl apply -f "$TEMP_DIR/app-deployment.yaml"
kubectl apply -f "$TEMP_DIR/app-service.yaml"
# Expected: deployment.apps/vuln-app created
#           service/vuln-app created

# Step 5: Deploy the AI service
kubectl apply -f "$TEMP_DIR/ai-deployment.yaml"
kubectl apply -f "$TEMP_DIR/ai-service.yaml"
# Expected: deployment.apps/ai-service created
#           service/ai-service created
```

### 5.5 Clean Up Temporary Manifests

```bash
rm -rf "$TEMP_DIR"
cd ..
```

### 5.6 Wait for Pods to Be Ready

```bash
kubectl -n ai-governance wait --for=condition=ready pod -l app=vuln-app --timeout=180s
kubectl -n ai-governance wait --for=condition=ready pod -l app=ai-service --timeout=180s
```

Expected:
```text
pod/vuln-app-xxxxxxxxxx-xxxxx condition met
pod/ai-service-xxxxxxxxxx-xxxxx condition met
```

---

## Phase 6: Verify Deployment

### 6.1 Check Pod Status

```bash
kubectl get pods -n ai-governance -o wide
```

Expected:
```text
NAME                          READY   STATUS    RESTARTS   AGE   IP           NODE
vuln-app-xxxxxxxxxx-xxxxx     1/1     Running   0          2m    10.0.x.x     gke-vuln-...
ai-service-xxxxxxxxxx-xxxxx   1/1     Running   0          2m    10.0.x.x     gke-vuln-...
```

### 6.2 Check Services

```bash
kubectl get svc -n ai-governance
```

Expected:
```text
NAME         TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
vuln-app     NodePort    10.2.x.x       <none>        8080:30080/TCP   2m
ai-service   ClusterIP   10.2.x.x       <none>        8081/TCP         2m
```

### 6.3 Get the Application URL

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "=========================================="
echo "  App URL: http://$NODE_IP:30080"
echo "=========================================="
```

### 6.4 Test the Application

```bash
# Health check
curl -s http://$NODE_IP:30080/health?check=basic | python3 -m json.tool
```

Expected:
```json
{
    "service": "gcc-governance-api",
    "status": "healthy"
}
```

```bash
# Dashboard (should return HTML)
curl -s http://$NODE_IP:30080/ | head -5
```

Expected:
```html
<!DOCTYPE html>
<html>
<head>
    <title>GCC AI Governance Dashboard</title>
```

```bash
# Policy search
curl -s "http://$NODE_IP:30080/search?q=SAMA" | python3 -m json.tool
```

Expected: JSON response with SAMA-CSF policy entries.

### 6.5 Verify GCS Bucket Contents

```bash
gsutil ls -r gs://vuln-ai-governance-data-$PROJECT_ID/
```

Expected:
```text
gs://vuln-ai-governance-data-your-project/data/knowledge_base/financial_policies.txt
gs://vuln-ai-governance-data-your-project/data/sample_pii.json
```

### 6.6 Verify Vertex AI API

```bash
gcloud services list --enabled --filter="name:aiplatform" --project=$PROJECT_ID
```

Expected:
```text
NAME                       TITLE
aiplatform.googleapis.com  Vertex AI API
```

---

## Phase 7: Begin Labs

Save the Node IP for use in all labs:

```bash
export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
echo "export NODE_IP=$NODE_IP" >> ~/.bashrc
echo "Lab environment ready. App URL: http://$NODE_IP:30080"
```

### Recommended Starting Order

| Order | Lab | Title | Duration |
|-------|-----|-------|----------|
| 1 | [Lab 01](../labs/lab01-code-injection.md) | Code Injection & SSRF | 30 min |
| 2 | [Lab 06](../labs/lab06-code-to-container.md) | Code to Container Pivot | 30 min |
| 3 | [Lab 02](../labs/lab02-container-misconfig.md) | Container Misconfiguration | 25 min |
| 4 | [Lab 07](../labs/lab07-container-to-cluster.md) | Container to Cluster Pivot | 40 min |
| 5 | [Lab 03](../labs/lab03-cluster-exploitation.md) | Cluster Exploitation | 40 min |
| 6 | [Lab 08](../labs/lab08-cluster-to-cloud.md) | Cluster to Cloud Pivot | 40 min |
| 7 | [Lab 04](../labs/lab04-cloud-escalation.md) | Cloud Privilege Escalation | 40 min |
| 8 | [Lab 09](../labs/lab09-cloud-to-ai.md) | Cloud to AI Pivot | 35 min |
| 9 | [Lab 05](../labs/lab05-ai-prompt-injection.md) | AI Prompt Injection | 35 min |
| 10 | [Lab 10](../labs/lab10-ai-to-code.md) | AI to Code Pivot | 35 min |
| 11 | [Lab 11](../labs/lab11-full-attack-chain.md) | Full Attack Chain | 90 min |

Total lab time: ~7 hours

---

## Automated Deployment (Alternative)

If you prefer a single-command deployment, the scripts handle all phases automatically:

```bash
export GCP_PROJECT_ID="your-project-id"

# Step 1: Setup (Phase 1-2)
./scripts/setup.sh

# Step 2: Deploy (Phase 3-6)
./scripts/deploy.sh
```

The `deploy.sh` script runs Phase 3 through 6 sequentially and prints the application URL at the end.

---

## Cleanup (Run After Completing Labs)

```bash
./scripts/cleanup.sh
```

When prompted, type `destroy` to confirm. This removes, in order:

1. **Kubernetes resources**: Namespaces, ClusterRoles, ClusterRoleBindings
2. **Container images**: `gcr.io/$PROJECT_ID/vuln-app` and `vuln-ai-service`
3. **Terraform resources**: GKE cluster, node pool, VPC, subnet, firewall rules, GCS bucket, IAM service account and key
4. **Local state**: `.terraform/`, `terraform.tfstate`, `tfplan`, `governance.db`

### Manual Cleanup (If Script Fails)

```bash
# Delete the entire GCP project (nuclear option - removes everything)
gcloud projects delete $PROJECT_ID
```

---

## Troubleshooting

### "Quota 'CPUS' exceeded" During Terraform Apply

```bash
gcloud compute regions describe us-central1 --project=$PROJECT_ID \
  --format="table(quotas.filter(metric='CPUS').limit, quotas.filter(metric='CPUS').usage)"
```

Fix: Request quota increase at Cloud Console > IAM & Admin > Quotas, or use a smaller machine type:
```bash
echo 'machine_type = "e2-standard-2"' >> terraform/terraform.tfvars
```

### Pods Stuck in ImagePullBackOff

```bash
# Check pod events
kubectl describe pod -n ai-governance -l app=vuln-app | tail -20

# Verify images exist in GCR
gcloud container images list --repository=gcr.io/$PROJECT_ID

# Re-push if missing
docker push gcr.io/$PROJECT_ID/vuln-app:latest
docker push gcr.io/$PROJECT_ID/vuln-ai-service:latest
```

### Pods Stuck in CrashLoopBackOff

```bash
# Check logs
kubectl logs -n ai-governance -l app=vuln-app --tail=50
kubectl logs -n ai-governance -l app=ai-service --tail=50
```

Common causes:
- Missing environment variables (check deployment YAML substitution)
- Python import errors (check Dockerfile build logs)

### Cannot Access NodePort from External IP

```bash
# Verify firewall rule
gcloud compute firewall-rules list --project=$PROJECT_ID --filter="name~nodeports"

# If missing, create manually
gcloud compute firewall-rules create allow-nodeports \
  --network=vuln-network \
  --allow=tcp:30000-32767 \
  --source-ranges=0.0.0.0/0 \
  --project=$PROJECT_ID

# Alternative: use kubectl port-forward
kubectl port-forward -n ai-governance svc/vuln-app 8080:8080
# Then access at http://localhost:8080
```

### Terraform State Lock Error

```bash
# If you get a state lock error, force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### "Permission denied" on Vertex AI API Calls

```bash
# Verify node SA has aiplatform.admin
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/aiplatform.admin" \
  --format="table(bindings.members)"

# If missing, add it manually
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:vuln-gke-node-sa@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/aiplatform.admin"
```

### GKE Cluster Creation Timeout

GKE creation can take 10-15 minutes. If terraform times out:

```bash
# Check cluster status
gcloud container clusters list --project=$PROJECT_ID

# If status is PROVISIONING, wait and re-run
terraform apply
```

---

## Estimated Cost Breakdown

| Resource | Specification | Cost/Hour | Cost/Day |
|----------|--------------|-----------|----------|
| GKE Node Pool | 2x e2-standard-4 (4 vCPU, 16GB each) | $0.20 | $4.80 |
| GKE Management Fee | Zonal cluster (free tier) | $0.00 | $0.00 |
| GCS Storage | ~1 MB stored | < $0.01 | < $0.01 |
| Network Egress | ~100 MB/day estimated | $0.01 | $0.01 |
| Vertex AI (Gemini Flash) | ~50-100 requests/day | $0.01 | $0.01-0.10 |
| Container Registry | ~500 MB stored | < $0.01 | < $0.01 |
| **Total** | | **~$0.22/hr** | **~$5-10/day** |

**Run `./scripts/cleanup.sh` immediately after lab completion to stop all charges.**
