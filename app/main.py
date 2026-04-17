import subprocess
import os
import sqlite3
import requests
from flask import Flask, request, render_template, jsonify, send_file
from config import *

# =============================================================================
# 5C Security Lab - Vulnerable Flask Application (Code Layer)
# VULNERABILITIES:
#   - OS Command Injection (CWE-78, OWASP A03)
#   - SQL Injection (CWE-89, OWASP A03)
#   - Path Traversal (CWE-22, OWASP A01)
#   - SSRF (CWE-918, OWASP A10)
#   - XSS via AI output (CWE-79, OWASP A03)
#   - Debug mode enabled (CWE-489, OWASP A05)
#   - Hardcoded secrets (CWE-798, OWASP A05)
#   - No rate limiting, no CSRF, no CSP
# =============================================================================

app = Flask(__name__)
app.config["SECRET_KEY"] = SECRET_KEY
app.debug = DEBUG


def init_db():
    conn = sqlite3.connect("governance.db")
    c = conn.cursor()
    c.execute(
        """CREATE TABLE IF NOT EXISTS policies
                 (id INTEGER PRIMARY KEY, name TEXT, category TEXT,
                  description TEXT, compliance_framework TEXT)"""
    )
    sample_policies = [
        ("SAMA-CSF-3.1.2", "Secure Coding", "Implement input validation on all endpoints", "SAMA-CSF"),
        ("SAMA-CSF-3.2.1", "IAM", "Enforce least privilege for all service accounts", "SAMA-CSF"),
        ("SAMA-CSF-3.3.4", "Encryption", "Encrypt all data at rest using CMEK", "SAMA-CSF"),
        ("NCA-ECC-1-1-3", "Access Control", "Restrict privileged access management", "NCA-ECC"),
        ("NCA-ECC-2-2-1", "Network", "Enforce default-deny network segmentation", "NCA-ECC"),
        ("NCA-ECC-2-3-1", "Container", "Run containers as non-root users", "NCA-ECC"),
        ("NCA-ECC-2-6-1", "Monitoring", "Enable audit logging for all API operations", "NCA-ECC"),
        ("NCA-CCC-2-1-4", "Cloud", "Enforce IMDSv2 on all compute instances", "NCA-CCC"),
        ("PDPL-Art-9", "Privacy", "Obtain consent before processing sensitive PII", "PDPL"),
        ("PDPL-Art-12", "Privacy", "Minimize PII retention to necessary scope", "PDPL"),
        ("PDPL-Art-14", "Privacy", "Segregate data belonging to different entities", "PDPL"),
        ("PDPL-Art-19", "Privacy", "Implement technical measures against data breaches", "PDPL"),
    ]
    c.executemany("INSERT OR IGNORE INTO policies VALUES (NULL,?,?,?,?)", sample_policies)
    conn.commit()
    conn.close()


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/lab")
def lab_dashboard():
    return render_template("dashboard.html")


# VULNERABILITY: OS Command Injection (OWASP A03:2021)
# User input passed directly to shell via subprocess with shell=True
@app.route("/health")
def health():
    check_type = request.args.get("check", "basic")
    if check_type == "basic":
        return jsonify({"status": "healthy", "service": "gcc-governance-api"})
    result = subprocess.run(
        f"echo 'Health check: {check_type}'",
        shell=True,
        capture_output=True,
        text=True,
    )
    return jsonify({"status": result.stdout, "errors": result.stderr})


# VULNERABILITY: SQL Injection (OWASP A03:2021)
# String concatenation in SQL query instead of parameterized queries
@app.route("/search")
def search():
    query = request.args.get("q", "")
    conn = sqlite3.connect("governance.db")
    try:
        results = conn.execute(
            f"SELECT * FROM policies WHERE name LIKE '%{query}%' "
            f"OR category LIKE '%{query}%' "
            f"OR description LIKE '%{query}%'"
        ).fetchall()
        policies = [
            {"id": r[0], "name": r[1], "category": r[2], "description": r[3], "framework": r[4]}
            for r in results
        ]
        return jsonify({"results": policies, "count": len(policies)})
    except Exception as e:
        return jsonify({"error": str(e), "query": query}), 500
    finally:
        conn.close()


# VULNERABILITY: Path Traversal (OWASP A01:2021)
# No validation on file path - allows reading arbitrary files
@app.route("/download")
def download():
    file_path = request.args.get("file", "")
    if not file_path:
        return jsonify({"error": "No file specified"}), 400
    try:
        full_path = os.path.join("/app/data", file_path)
        return send_file(full_path)
    except Exception as e:
        return jsonify({"error": str(e)}), 404


# VULNERABILITY: Server-Side Request Forgery (OWASP A10:2021)
# No URL allowlist - allows internal network scanning and metadata access
@app.route("/fetch", methods=["POST"])
def fetch():
    data = request.get_json()
    url = data.get("url", "") if data else ""
    if not url:
        return jsonify({"error": "No URL provided"}), 400
    try:
        resp = requests.get(url, timeout=5)
        return jsonify({"status_code": resp.status_code, "body": resp.text[:5000]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# VULNERABILITY: Proxy to AI service without input sanitization
# AI response rendered with |safe in template (XSS via AI output)
@app.route("/ai/query", methods=["POST"])
def ai_query():
    data = request.get_json()
    prompt = data.get("prompt", "") if data else ""
    if not prompt:
        return jsonify({"error": "No prompt provided"}), 400
    try:
        resp = requests.post(
            f"{AI_SERVICE_URL}/generate",
            json={"prompt": prompt},
            timeout=30,
        )
        return jsonify(resp.json())
    except Exception as e:
        return jsonify({"error": str(e), "ai_service_url": AI_SERVICE_URL}), 500


# VULNERABILITY: Verbose error handler exposing stack traces (OWASP A05:2021)
@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        "error": str(error),
        "debug": DEBUG,
        "secret_key_hint": SECRET_KEY[:10] + "...",
    }), 500


if __name__ == "__main__":
    init_db()
    app.run(host=HOST, port=PORT, debug=DEBUG)
