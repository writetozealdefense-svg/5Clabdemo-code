# Lab 02: Container Misconfiguration
> **Layer**: Container | **Difficulty**: Beginner | **Duration**: 25 min

## Objective

Identify and exploit common container security misconfigurations in a Kubernetes pod. Participants will discover that the application container runs as root, exposes sensitive environment variables, includes unnecessary tools, and lacks filesystem restrictions -- all of which violate container hardening best practices and expand the attack surface.

## OWASP Mapping

- **A05:2021 -- Security Misconfiguration**: Running as root, writable filesystem, unnecessary packages installed
- **A02:2021 -- Cryptographic Failures**: Secrets exposed as plaintext environment variables
- **A08:2021 -- Software and Data Integrity Failures**: Mutable container with no image verification

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| NIST 800-53 | CM-6 | Configuration Settings -- containers must follow hardened baselines |
| NIST 800-53 | CM-7 | Least Functionality -- remove unnecessary tools and packages |
| CIS Kubernetes | 5.2.6 | Minimize containers running as root |
| CIS Kubernetes | 5.2.7 | Minimize containers with added capabilities |
| CIS Docker | 4.1 | Ensure a non-root user is created for the container |
| ISO 27001 | A.12.6.1 | Management of technical vulnerabilities |

## Prerequisites

- `kubectl` configured with access to the GKE cluster
- The vulnerable application pod is running in the `ai-governance` namespace
- Basic familiarity with Linux commands and Kubernetes pod operations

## Attack Steps

### Step 1: Exec Into the Vulnerable Pod

Open an interactive shell session inside the running application container.

```bash
kubectl exec -it deploy/vuln-app -n ai-governance -- /bin/bash
```

**Expected Output:**
```text
root@vuln-app-xxxxx:/app#
```

**Explanation:**
The `kubectl exec` command opens a shell inside the running container. The prompt immediately reveals two problems: the shell is running as `root` (shown in the prompt), and `/bin/bash` is available, meaning a full shell interpreter is installed. In a hardened container, interactive shells would not be present, and the process would run as an unprivileged user.

---

### Step 2: Confirm Root Execution

Verify the effective user identity inside the container.

```bash
whoami
```

**Expected Output:**
```text
root
```

**Explanation:**
The container process runs as UID 0 (root). This means any code execution vulnerability -- whether from application bugs or a compromised dependency -- grants the attacker full root privileges within the container. Combined with a privileged security context, this can lead to container escape and host compromise.

---

### Step 3: Read the Shadow Password File

Attempt to read the shadow file, which should be restricted to root only.

```bash
cat /etc/shadow
```

**Expected Output:**
```text
root:*:19000:0:99999:7:::
daemon:*:19000:0:99999:7:::
bin:*:19000:0:99999:7:::
...
```

**Explanation:**
The `/etc/shadow` file contains password hashes and is readable only by root. Successfully reading this file confirms unrestricted root access. In a properly configured container, the process would run as a non-root user and this file would be inaccessible, even if the container image includes it.

---

### Step 4: Extract Secrets from Environment Variables

Search the environment for credentials, API keys, or other sensitive values that may have been injected via Kubernetes environment variable configurations.

```bash
env | grep -iE "secret|password|key|token|api"
```

**Expected Output:**
```text
DATABASE_PASSWORD=supersecretpassword123
API_KEY=AIza...
SECRET_KEY=flask-secret-key-changeme
...
```

**Explanation:**
Kubernetes allows injecting secrets as environment variables into pods. However, environment variables are visible to any process running in the container, are logged by many frameworks, and appear in process listings. This violates the principle of least exposure. Secrets should instead be mounted as files with restricted permissions or retrieved from a secrets manager at runtime.

---

### Step 5: Inventory Installed Attack Tools

Check whether common network reconnaissance and data exfiltration tools are available inside the container.

```bash
which nmap curl wget dig nslookup
```

**Expected Output:**
```text
/usr/bin/nmap
/usr/bin/curl
/usr/bin/wget
/usr/bin/dig
/usr/bin/nslookup
```

**Explanation:**
The container image includes network scanning tools (nmap), HTTP clients (curl, wget), and DNS utilities (dig, nslookup). These are unnecessary for the application's function and provide an attacker with a ready-made toolkit for network reconnaissance, lateral movement, and data exfiltration. Production containers should use minimal or distroless base images that contain only the application binary and its runtime dependencies.

---

### Step 6: Scan the Local Network Subnet

Use the pre-installed nmap to discover other hosts on the pod network.

```bash
nmap -sn 10.0.0.0/24 2>/dev/null | grep "Nmap scan report"
```

**Expected Output:**
```text
Nmap scan report for 10.0.0.1
Nmap scan report for 10.0.0.2
Nmap scan report for 10.0.0.5
...
```

**Explanation:**
With nmap available, the attacker can perform a ping sweep of the pod CIDR to discover other running services. This is the first step in lateral movement: identifying targets. In a properly configured cluster, NetworkPolicies would restrict pod-to-pod traffic, and the absence of nmap in the image would prevent this reconnaissance entirely.

---

### Step 7: Verify Writable Filesystem

Check whether the container's root filesystem is mounted read-write, allowing an attacker to modify binaries, plant backdoors, or tamper with application files.

```bash
ls -la /
touch /testfile && echo "Filesystem is writable" && rm /testfile
```

**Expected Output:**
```text
Filesystem is writable
```

**Explanation:**
The container filesystem is writable, meaning an attacker can create new files, modify existing binaries, or install additional tools. A read-only root filesystem (`readOnlyRootFilesystem: true` in the security context) prevents this by making the entire filesystem immutable at runtime. Temporary directories like `/tmp` can be mounted separately as writable if the application requires them.

---

### Step 8: Inspect the Container Base Image

Examine the operating system release information to determine the base image and whether it follows minimal image practices.

```bash
cat /etc/os-release
```

**Expected Output:**
```text
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
VERSION="12 (bookworm)"
...
```

**Explanation:**
The container is built on a full Debian base image rather than a minimal or distroless image. Full OS images include package managers, shells, utilities, and libraries that expand the attack surface and increase the number of potential CVEs. Distroless images or Alpine-based images contain only the language runtime and application, drastically reducing what an attacker can leverage after gaining access.

## Remediation

1. **Non-Root User**: Add a `USER` directive in the Dockerfile to run the application as an unprivileged user. Set `runAsNonRoot: true` and `runAsUser` in the pod security context.
2. **Distroless Base Images**: Rebuild the container using `gcr.io/distroless/python3` or a similar minimal image that excludes shells, package managers, and system utilities.
3. **Drop Capabilities**: Set `allowPrivilegeEscalation: false` and drop all Linux capabilities with `drop: ["ALL"]` in the security context. Only add back specific capabilities if absolutely required.
4. **Read-Only Root Filesystem**: Enable `readOnlyRootFilesystem: true` in the security context. Mount `/tmp` as an `emptyDir` volume if the application needs temporary file storage.
5. **Remove Unnecessary Tools**: Eliminate nmap, curl, wget, dig, and other utilities from the container image. If build-stage tools are needed, use multi-stage Docker builds to exclude them from the final image.
6. **Externalize Secrets**: Replace environment variable injection with Kubernetes Secrets mounted as files, or integrate with GCP Secret Manager using workload identity. Rotate secrets regularly.

## Key Takeaways

- Running containers as root is the single most impactful misconfiguration because it amplifies every other vulnerability.
- Pre-installed tools inside containers provide attackers with everything they need for reconnaissance and lateral movement without requiring any additional downloads.
- A writable filesystem allows persistent modification of the container, enabling backdoors that survive application restarts within the same pod lifecycle.
- Container hardening is a foundational layer: even strong application code is undermined if the container it runs in is misconfigured.
