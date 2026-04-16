# =============================================================================
# 5C Security Lab - Rebuild + Redeploy Script (Windows PowerShell)
#
# Runs the complete update workflow after changing app code or K8s manifests:
#   1. Pulls latest code from git
#   2. Rebuilds both Docker images via Cloud Build (no local Docker needed)
#   3. Re-applies K8s manifests (with placeholder substitution)
#   4. Forces a rolling restart to pick up :latest image changes
#   5. Waits for pods to be ready
#   6. Runs smoke tests against the new pods
#   7. Prints access URLs
#
# Usage:
#   $env:PROJECT_ID = "lab-5csec-317009"
#   .\scripts\rebuild-redeploy.ps1
#
# Environment overrides:
#   $env:PROJECT_ID    - GCP project ID (required)
#   $env:ZONE          - GKE zone (default: us-central1-a)
#   $env:CLUSTER_NAME  - GKE cluster (default: vuln-gke-cluster)
#   $env:BUCKET_NAME   - GCS bucket (default: vuln-ai-governance-data-<PROJECT_ID>)
#   $env:SKIP_BUILD    - Set to "1" to skip Cloud Build and reuse existing GCR images
#   $env:SKIP_GIT_PULL - Set to "1" to skip 'git pull'
# =============================================================================

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Section($Text) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  $Text" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
}

function Write-Ok($Text)   { Write-Host "[OK] $Text"   -ForegroundColor Green }
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

$totalStart = Get-Date

# -----------------------------------------------------------------------------
# Step 1: Resolve Configuration
# -----------------------------------------------------------------------------
Write-Section "Step 1/7: Resolving Configuration"

$PROJECT_ID = $env:PROJECT_ID
if (-not $PROJECT_ID) {
    $PROJECT_ID = (gcloud config get-value project 2>&1 | Out-String).Trim()
}
if (-not $PROJECT_ID -or $PROJECT_ID -eq "(unset)") {
    Write-Fail "PROJECT_ID not set. Run: `$env:PROJECT_ID = 'your-project-id'"
}

$ZONE         = if ($env:ZONE)         { $env:ZONE }         else { "us-central1-a" }
$CLUSTER_NAME = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "vuln-gke-cluster" }
$BUCKET_NAME  = if ($env:BUCKET_NAME)  { $env:BUCKET_NAME }  else { "vuln-ai-governance-data-$PROJECT_ID" }

$APP_IMAGE = "gcr.io/$PROJECT_ID/vuln-app:latest"
$AI_IMAGE  = "gcr.io/$PROJECT_ID/vuln-ai-service:latest"

Write-Log "Project:      $PROJECT_ID"
Write-Log "Zone:         $ZONE"
Write-Log "Cluster:      $CLUSTER_NAME"
Write-Log "Bucket:       $BUCKET_NAME"
Write-Log "App image:    $APP_IMAGE"
Write-Log "AI image:     $AI_IMAGE"

# -----------------------------------------------------------------------------
# Step 2: Pull Latest Code (unless SKIP_GIT_PULL=1)
# -----------------------------------------------------------------------------
Write-Section "Step 2/7: Pulling Latest Code from Git"

if ($env:SKIP_GIT_PULL -eq "1") {
    Write-Warn "SKIP_GIT_PULL=1 - skipping git pull"
} else {
    Set-Location $ProjectRoot
    $stepStart = Get-Date
    git pull origin main
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "git pull failed - continuing with current code"
    } else {
        Write-Ok "Git pull complete ($(((Get-Date) - $stepStart).TotalSeconds.ToString('F1'))s)"
    }
}

# -----------------------------------------------------------------------------
# Step 3: Rebuild Images via Cloud Build
# -----------------------------------------------------------------------------
Write-Section "Step 3/7: Rebuilding Docker Images via Cloud Build"

if ($env:SKIP_BUILD -eq "1") {
    Write-Warn "SKIP_BUILD=1 - skipping Cloud Build, reusing existing images"
} else {
    Set-Location $ProjectRoot

    if (-not (Test-Path "cloudbuild.yaml")) {
        Write-Fail "cloudbuild.yaml not found in $ProjectRoot"
    }

    $stepStart = Get-Date
    Write-Log "Submitting to Cloud Build (this takes ~3-5 minutes)..."

    gcloud builds submit --config cloudbuild.yaml .
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Cloud Build failed. Check logs in Cloud Console."
    }
    Write-Ok "Images rebuilt and pushed ($(((Get-Date) - $stepStart).TotalSeconds.ToString('F1'))s)"
}

# -----------------------------------------------------------------------------
# Step 4: Verify Cluster Connection
# -----------------------------------------------------------------------------
Write-Section "Step 4/7: Verifying Cluster Connection"

kubectl cluster-info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log "kubectl not connected. Fetching credentials..."
    gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE --project $PROJECT_ID
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to get cluster credentials"
    }
}
Write-Ok "Connected to cluster $CLUSTER_NAME"

# -----------------------------------------------------------------------------
# Step 5: Re-apply Kubernetes Manifests
# -----------------------------------------------------------------------------
Write-Section "Step 5/7: Re-applying Kubernetes Manifests"

$manifestsDir = Join-Path $ProjectRoot "kubernetes"
$tempDir      = Join-Path $env:TEMP "5clab-redeploy-$([guid]::NewGuid().ToString().Substring(0,8))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    Write-Log "Preparing manifests (substituting placeholders)..."
    Copy-Item -Path "$manifestsDir\*.yaml" -Destination $tempDir

    Get-ChildItem $tempDir -Filter *.yaml | ForEach-Object {
        (Get-Content $_.FullName -Raw) `
            -replace 'REPLACE_APP_IMAGE',    $APP_IMAGE `
            -replace 'REPLACE_AI_IMAGE',     $AI_IMAGE `
            -replace 'REPLACE_BUCKET_NAME',  $BUCKET_NAME `
            -replace 'REPLACE_PROJECT_ID',   $PROJECT_ID |
            Set-Content -Path $_.FullName -NoNewline
    }

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
        if ($LASTEXITCODE -ne 0) { Write-Warn "Failed to apply $m (continuing)" }
    }
    Write-Ok "All manifests applied"
} finally {
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
}

# -----------------------------------------------------------------------------
# Step 6: Force Rolling Restart to Pick Up New Images
# -----------------------------------------------------------------------------
Write-Section "Step 6/7: Rolling Restart (pull new :latest images)"

Write-Log "Restarting deployments..."
kubectl rollout restart deployment/vuln-app -n ai-governance
kubectl rollout restart deployment/ai-service -n ai-governance

Write-Log "Waiting for rollouts to complete..."
$stepStart = Get-Date

kubectl rollout status deployment/vuln-app -n ai-governance --timeout=180s
$appStatus = $LASTEXITCODE
if ($appStatus -eq 0) { Write-Ok "vuln-app rollout complete" } else { Write-Warn "vuln-app rollout did not complete in 180s" }

kubectl rollout status deployment/ai-service -n ai-governance --timeout=180s
$aiStatus = $LASTEXITCODE
if ($aiStatus -eq 0) { Write-Ok "ai-service rollout complete" } else { Write-Warn "ai-service rollout did not complete in 180s" }

Write-Log "Rollout step took $(((Get-Date) - $stepStart).TotalSeconds.ToString('F1'))s"

# -----------------------------------------------------------------------------
# Step 7: Verify and Smoke Test
# -----------------------------------------------------------------------------
Write-Section "Step 7/7: Verification and Smoke Tests"

Write-Host ""
Write-Log "Pod status:"
kubectl get pods -n ai-governance -o wide

Write-Host ""
Write-Log "Service status:"
kubectl get svc -n ai-governance

# Extract node external IP using ConvertFrom-Json (no jsonpath quoting issues)
$NODE_IP = ""
try {
    $nodesJson = kubectl get nodes -o json 2>$null | ConvertFrom-Json
    foreach ($node in $nodesJson.items) {
        $extIP = $node.status.addresses | Where-Object { $_.type -eq "ExternalIP" } | Select-Object -First 1 -ExpandProperty address
        if ($extIP) { $NODE_IP = $extIP; break }
    }
} catch {
    Write-Warn "Could not parse node JSON"
}

if (-not $NODE_IP) {
    Write-Warn "No external node IP found. Use port-forward: kubectl port-forward -n ai-governance svc/vuln-app 8080:8080"
} else {
    Write-Host ""
    Write-Log "Smoke testing http://${NODE_IP}:30080 ..."

    # App health check
    try {
        $resp = Invoke-WebRequest -Uri "http://${NODE_IP}:30080/health?check=basic" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.StatusCode -eq 200 -and $resp.Content -match "healthy") {
            Write-Ok "App health endpoint: HTTP 200 (healthy)"
        } else {
            Write-Warn "App health returned HTTP $($resp.StatusCode)"
        }
    } catch {
        Write-Warn "App health failed: $_"
        Write-Warn "Check pod logs: kubectl logs -n ai-governance -l app=vuln-app --tail=50"
    }

    # Dashboard
    try {
        $resp = Invoke-WebRequest -Uri "http://${NODE_IP}:30080/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Ok "Dashboard: HTTP 200"
        } else {
            Write-Warn "Dashboard returned HTTP $($resp.StatusCode)"
        }
    } catch {
        Write-Warn "Dashboard failed: $_"
    }
}

# -----------------------------------------------------------------------------
# Final Summary
# -----------------------------------------------------------------------------
$totalTime = ((Get-Date) - $totalStart).TotalSeconds

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  REBUILD + REDEPLOY COMPLETE" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Total time:  $($totalTime.ToString('F1'))s" -ForegroundColor Green
Write-Host "  Project:     $PROJECT_ID" -ForegroundColor Green
Write-Host "  Cluster:     $CLUSTER_NAME" -ForegroundColor Green
if ($NODE_IP) {
    Write-Host "  App URL:     http://${NODE_IP}:30080" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Save for labs:"
    Write-Host "    `$env:NODE_IP = '$NODE_IP'" -ForegroundColor White
    Write-Host "    `$env:PROJECT_ID = '$PROJECT_ID'" -ForegroundColor White
    Write-Host ""
    Write-Host "  Quick test:"
    Write-Host "    curl.exe `"http://${NODE_IP}:30080/health?check=basic`"" -ForegroundColor White
    Write-Host "    curl.exe `"http://${NODE_IP}:30080/health?check=basic';id;echo'`"" -ForegroundColor White
}
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    Dashboard:      .\scripts\show-status.ps1"
Write-Host "    Start Lab 01:   labs/lab01-code-injection.md"
Write-Host ""
Write-Host "  If pods still crash:"
Write-Host "    kubectl logs -n ai-governance -l app=vuln-app --tail=50"
Write-Host "    kubectl logs -n ai-governance -l app=ai-service --tail=50"
Write-Host ""
