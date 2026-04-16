# =============================================================================
# 5C Security Lab - Kubernetes Deploy Script (Windows PowerShell)
#
# Deploys the vulnerable app and AI service to an existing GKE cluster.
# Assumes:
#   - Terraform infrastructure is already deployed (GKE cluster exists)
#   - Both Docker images are already in GCR (via Cloud Build or local push)
#   - gcloud is authenticated and project is set
#
# Usage (from PowerShell):
#   $env:PROJECT_ID = "lab-5csec-317009"
#   .\scripts\deploy-k8s.ps1
#
# Environment overrides:
#   $env:PROJECT_ID   - GCP project ID (required if not set via gcloud config)
#   $env:ZONE         - GKE zone (default: us-central1-a)
#   $env:CLUSTER_NAME - GKE cluster name (default: vuln-gke-cluster)
#   $env:BUCKET_NAME  - GCS bucket (default: vuln-ai-governance-data-<PROJECT_ID>)
# =============================================================================

# Use Continue (not Stop) so that benign stderr output from native commands
# (e.g. gcloud WARNINGs) doesn't terminate the script. We check $LASTEXITCODE
# explicitly after each native call instead.
$ErrorActionPreference = "Continue"

# In PowerShell 7.3+, this prevents stderr output being treated as an error.
# In older versions, the setting is silently ignored.
$PSNativeCommandUseErrorActionPreference = $false

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
function Write-Section($Text) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  $Text" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
}

function Write-Ok($Text)   { Write-Host "[OK] $Text" -ForegroundColor Green }
function Write-Warn($Text) { Write-Host "[WARN] $Text" -ForegroundColor Yellow }
function Write-Fail($Text) {
    Write-Host "[ERROR] $Text" -ForegroundColor Red
    exit 1
}
function Write-Log($Text) {
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $Text" -ForegroundColor Blue
}

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptDir

# -----------------------------------------------------------------------------
# Step 1: Prerequisite Check
# -----------------------------------------------------------------------------
Write-Section "Step 1/6: Checking Prerequisites"

$missing = $false
foreach ($cmd in @("gcloud", "kubectl")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Ok "$cmd found"
    } else {
        Write-Warn "$cmd is MISSING"
        $missing = $true
    }
}
if ($missing) {
    Write-Fail "Install missing prerequisites. For kubectl: gcloud components install kubectl"
}

# -----------------------------------------------------------------------------
# Step 2: Resolve Configuration
# -----------------------------------------------------------------------------
Write-Section "Step 2/6: Resolving Configuration"

# PROJECT_ID
$PROJECT_ID = $env:PROJECT_ID
if (-not $PROJECT_ID) {
    $PROJECT_ID = (gcloud config get-value project 2>&1 | Out-String).Trim()
}
if (-not $PROJECT_ID -or $PROJECT_ID -eq "(unset)") {
    Write-Fail "Cannot determine PROJECT_ID. Set it: `$env:PROJECT_ID = 'your-project-id'"
}

$ZONE         = if ($env:ZONE)         { $env:ZONE }         else { "us-central1-a" }
$CLUSTER_NAME = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "vuln-gke-cluster" }
$BUCKET_NAME  = if ($env:BUCKET_NAME)  { $env:BUCKET_NAME }  else { "vuln-ai-governance-data-$PROJECT_ID" }

$APP_IMAGE = "gcr.io/$PROJECT_ID/vuln-app:latest"
$AI_IMAGE  = "gcr.io/$PROJECT_ID/vuln-ai-service:latest"

Write-Log "Project:     $PROJECT_ID"
Write-Log "Zone:        $ZONE"
Write-Log "Cluster:     $CLUSTER_NAME"
Write-Log "Bucket:      $BUCKET_NAME"
Write-Log "App image:   $APP_IMAGE"
Write-Log "AI image:    $AI_IMAGE"

# -----------------------------------------------------------------------------
# Step 3: Verify Cluster + Images
# -----------------------------------------------------------------------------
Write-Section "Step 3/6: Verifying Preconditions"

gcloud container clusters describe $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "GKE cluster '$CLUSTER_NAME' not found in $ZONE.`n    Run terraform apply first."
}
Write-Ok "GKE cluster '$CLUSTER_NAME' exists"

foreach ($img in @("vuln-app", "vuln-ai-service")) {
    gcloud container images describe "gcr.io/$PROJECT_ID/${img}:latest" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Image gcr.io/$PROJECT_ID/${img}:latest not found in GCR.`n    Build via: gcloud builds submit --config cloudbuild.yaml ."
    }
    Write-Ok "Image $img exists in GCR"
}

# -----------------------------------------------------------------------------
# Step 4: Configure kubectl
# -----------------------------------------------------------------------------
Write-Section "Step 4/6: Configuring kubectl"

Write-Log "Fetching cluster credentials..."
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID
if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to get cluster credentials" }

kubectl cluster-info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "kubectl cannot connect to the cluster" }
Write-Ok "kubectl connected to $CLUSTER_NAME"

Write-Log "Cluster nodes:"
kubectl get nodes --no-headers | ForEach-Object { Write-Host "  $_" }

# -----------------------------------------------------------------------------
# Step 5: Apply Kubernetes Manifests
# -----------------------------------------------------------------------------
Write-Section "Step 5/6: Deploying to Kubernetes"

$manifestsDir = Join-Path $ProjectRoot "kubernetes"
$tempDir      = Join-Path $env:TEMP "5clab-$([guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Log "Substituting placeholders..."
    Copy-Item -Path "$manifestsDir\*.yaml" -Destination $tempDir

    Get-ChildItem $tempDir -Filter *.yaml | ForEach-Object {
        (Get-Content $_.FullName -Raw) `
            -replace 'REPLACE_APP_IMAGE',    $APP_IMAGE `
            -replace 'REPLACE_AI_IMAGE',     $AI_IMAGE `
            -replace 'REPLACE_BUCKET_NAME',  $BUCKET_NAME `
            -replace 'REPLACE_PROJECT_ID',   $PROJECT_ID |
            Set-Content -Path $_.FullName -NoNewline
    }

    Write-Log "Applying manifests in dependency order..."
    $manifests = @(
        "namespaces.yaml",
        "serviceaccount.yaml",
        "rbac.yaml",
        "app-deployment.yaml",
        "app-service.yaml",
        "ai-deployment.yaml",
        "ai-service.yaml"
    )
    foreach ($m in $manifests) {
        kubectl apply -f (Join-Path $tempDir $m)
        if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to apply $m" }
    }
    Write-Ok "Manifests applied"

    Write-Log "Waiting for pods to become ready (up to 3 min)..."
    kubectl -n ai-governance wait --for=condition=ready pod -l app=vuln-app --timeout=180s
    if ($LASTEXITCODE -eq 0) { Write-Ok "vuln-app pod ready" } else { Write-Warn "vuln-app pod not ready after 180s" }

    kubectl -n ai-governance wait --for=condition=ready pod -l app=ai-service --timeout=180s
    if ($LASTEXITCODE -eq 0) { Write-Ok "ai-service pod ready" } else { Write-Warn "ai-service pod not ready after 180s" }

} finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}

# -----------------------------------------------------------------------------
# Step 6: Verify Deployment
# -----------------------------------------------------------------------------
Write-Section "Step 6/6: Verifying Deployment"

Write-Host ""
Write-Log "Pod status:"
kubectl get pods -n ai-governance -o wide

Write-Host ""
Write-Log "Service status:"
kubectl get svc -n ai-governance

Write-Host ""
# Use ConvertFrom-Json instead of jsonpath — PowerShell mangles the quotes
# inside [?(@.type=="ExternalIP")] which breaks kubectl's jsonpath parser.
$nodesJson = kubectl get nodes -o json | ConvertFrom-Json
$NODE_IP = ""
foreach ($node in $nodesJson.items) {
    $extIP = $node.status.addresses | Where-Object { $_.type -eq "ExternalIP" } | Select-Object -First 1 -ExpandProperty address
    if ($extIP) { $NODE_IP = $extIP; break }
}
if (-not $NODE_IP) {
    foreach ($node in $nodesJson.items) {
        $intIP = $node.status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -First 1 -ExpandProperty address
        if ($intIP) { $NODE_IP = $intIP; break }
    }
    Write-Warn "No external node IP. Use: kubectl port-forward -n ai-governance svc/vuln-app 8080:8080"
}

Write-Log "Smoke-testing the app..."
try {
    $resp = Invoke-WebRequest -Uri "http://${NODE_IP}:30080/health?check=basic" -UseBasicParsing -TimeoutSec 10
    if ($resp.StatusCode -eq 200) {
        Write-Ok "App responding on port 30080 (HTTP 200)"
    } else {
        Write-Warn "App returned HTTP $($resp.StatusCode)"
    }
} catch {
    Write-Warn "App did not respond within 10s: $_"
    Write-Warn "  Check firewall: gcloud compute firewall-rules list --filter=`"name~nodeports`""
    Write-Warn "  Check pod logs: kubectl logs -n ai-governance -l app=vuln-app"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App URL:     " -NoNewline; Write-Host "http://${NODE_IP}:30080" -ForegroundColor Green
Write-Host "  GCS Bucket:  " -NoNewline; Write-Host "gs://$BUCKET_NAME" -ForegroundColor Green
Write-Host "  Cluster:     " -NoNewline; Write-Host "$CLUSTER_NAME" -ForegroundColor Green
Write-Host "  Project:     " -NoNewline; Write-Host "$PROJECT_ID" -ForegroundColor Green
Write-Host ""
Write-Host "  Save for labs:"
Write-Host "    `$env:NODE_IP = '$NODE_IP'"
Write-Host "    `$env:PROJECT_ID = '$PROJECT_ID'"
Write-Host ""
Write-Host "  Start with Lab 01: labs/lab01-code-injection.md"
Write-Host ""
