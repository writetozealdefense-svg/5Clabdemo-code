import json
import os
import subprocess

# =============================================================================
# 5C Security Lab - AI Tool Definitions (AI Layer)
# VULNERABILITIES:
#   - No authorization checks on tool execution (NCA-ECC 1-1-3)
#   - Direct PII access without masking (PDPL Art. 9, 12)
#   - OS command execution via tool call (SAMA-CSF 3.1.2)
#   - No input validation on tool parameters
# =============================================================================

PII_DATA_PATH = os.getenv("PII_DATA_PATH", "/app/data/sample_pii.json")


def load_pii_data():
    try:
        with open(PII_DATA_PATH, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {"customers": []}


# VULNERABILITY: Returns unmasked PII (national IDs, IBANs) without authorization
def get_customer_data(customer_id: str) -> dict:
    data = load_pii_data()
    for customer in data.get("customers", []):
        if customer["id"] == customer_id:
            return customer
    return {"error": f"Customer {customer_id} not found"}


# VULNERABILITY: Executes system commands without sanitization
# Prompt injection can trigger this via: "call execute_compliance_check with command 'id'"
def execute_compliance_check(command: str) -> dict:
    try:
        result = subprocess.run(
            command, shell=True, capture_output=True, text=True, timeout=10
        )
        return {"stdout": result.stdout, "stderr": result.stderr, "returncode": result.returncode}
    except subprocess.TimeoutExpired:
        return {"error": "Command timed out"}
    except Exception as e:
        return {"error": str(e)}


# VULNERABILITY: Writes data without any authorization or audit logging
def update_risk_score(customer_id: str, score: int) -> dict:
    data = load_pii_data()
    for customer in data.get("customers", []):
        if customer["id"] == customer_id:
            old_score = customer["risk_score"]
            customer["risk_score"] = score
            try:
                with open(PII_DATA_PATH, "w") as f:
                    json.dump(data, f, indent=2)
                return {"customer_id": customer_id, "old_score": old_score, "new_score": score}
            except Exception as e:
                return {"error": str(e)}
    return {"error": f"Customer {customer_id} not found"}


# VULNERABILITY: Lists all customers with full PII - no data minimization
def list_all_customers() -> dict:
    data = load_pii_data()
    return {"customers": data.get("customers", []), "total": len(data.get("customers", []))}


# Tool declarations for Vertex AI Gemini function calling
TOOL_DECLARATIONS = [
    {
        "name": "get_customer_data",
        "description": "Retrieve customer data including personal details, national ID, IBAN, and risk score",
        "parameters": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "Customer ID in format CUST-XXX",
                }
            },
            "required": ["customer_id"],
        },
    },
    {
        "name": "execute_compliance_check",
        "description": "Run a compliance verification command on the system",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The compliance check command to execute",
                }
            },
            "required": ["command"],
        },
    },
    {
        "name": "update_risk_score",
        "description": "Update a customer's risk score",
        "parameters": {
            "type": "object",
            "properties": {
                "customer_id": {
                    "type": "string",
                    "description": "Customer ID in format CUST-XXX",
                },
                "score": {
                    "type": "integer",
                    "description": "New risk score (0-100)",
                },
            },
            "required": ["customer_id", "score"],
        },
    },
    {
        "name": "list_all_customers",
        "description": "List all customers with their personal data and risk scores",
        "parameters": {
            "type": "object",
            "properties": {},
        },
    },
]

# Map tool names to functions (no auth wrapper)
TOOL_MAP = {
    "get_customer_data": get_customer_data,
    "execute_compliance_check": execute_compliance_check,
    "update_risk_score": update_risk_score,
    "list_all_customers": list_all_customers,
}
