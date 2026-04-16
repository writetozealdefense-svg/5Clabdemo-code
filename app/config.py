import os

# =============================================================================
# 5C Security Lab - Application Configuration
# VULNERABILITIES:
#   - Hardcoded secrets (CWE-798, SAMA-CSF 3.2.3)
#   - Debug mode enabled in production (CWE-489, SAMA-CSF 3.1.4)
#   - No environment-based configuration management
# =============================================================================

# VULNERABILITY: Hardcoded credentials
DATABASE_URL = "sqlite:///governance.db"
SECRET_KEY = "super-secret-key-do-not-share-2024"
API_KEY = "sk-fake-api-key-1234567890abcdef"
ADMIN_PASSWORD = "admin123"
JWT_SECRET = "jwt-weak-secret"

# VULNERABILITY: Debug mode in production
DEBUG = True

# AI Service connection
AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "http://ai-service.ai-governance.svc.cluster.local:8081")

# GCS Bucket (set by env var in K8s deployment)
GCS_BUCKET = os.getenv("GCS_BUCKET", "vuln-ai-governance-data")

# Application settings
HOST = "0.0.0.0"
# Port 18080 (not 8080) to avoid conflict with GKE node services
# when running with hostNetwork: true (a deliberate vulnerability for Lab 07).
PORT = int(os.getenv("APP_PORT", "18080"))
