# =============================================================================
# 5C Security Lab - Vulnerable Application Dockerfile
# VULNERABILITIES:
#   - FROM python:latest (mutable tag, CWE-1104, OWASP A06)
#   - Runs as root (no USER directive, NCA-ECC 2-3-1)
#   - Installs attack tools (nmap, curl, wget, SAMA-CSF 3.3.6)
#   - Secrets in ENV variables (CWE-798, NCA-ECC 2-4-1)
#   - No HEALTHCHECK instruction
#   - No read-only filesystem capability
#   - No .dockerignore for sensitive files
# =============================================================================

# VULNERABILITY: Using mutable 'latest' tag instead of pinned digest
FROM python:latest

# VULNERABILITY: Installing offensive/recon tools in production image
RUN apt-get update && apt-get install -y \
    nmap \
    curl \
    wget \
    net-tools \
    dnsutils \
    iproute2 \
    procps \
    && rm -rf /var/lib/apt/lists/*

# VULNERABILITY: No USER directive - container runs as root (UID 0)
WORKDIR /app

# Copy application code
COPY app/ /app/
COPY ai/data/ /app/data/

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# VULNERABILITY: Secrets baked into environment variables
ENV SECRET_KEY="super-secret-key-do-not-share-2024"
ENV API_KEY="sk-fake-api-key-1234567890abcdef"
ENV ADMIN_PASSWORD="admin123"
ENV DATABASE_URL="sqlite:///governance.db"
ENV JWT_SECRET="jwt-weak-secret"

# VULNERABILITY: No HEALTHCHECK instruction
# VULNERABILITY: No read-only filesystem enforced

EXPOSE 8080

CMD ["python", "main.py"]
