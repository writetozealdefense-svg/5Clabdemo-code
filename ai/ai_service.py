import json
import os
from flask import Flask, request, jsonify
import vertexai
from vertexai.generative_models import GenerativeModel, Tool, FunctionDeclaration
from rag_service import RAGService
from tools import TOOL_DECLARATIONS, TOOL_MAP

# =============================================================================
# 5C Security Lab - AI Service (Vertex AI Gemini Integration)
# VULNERABILITIES:
#   - No system/user prompt separation (OWASP A03 - Prompt Injection)
#   - No output guardrails or PII filtering (PDPL Art. 9, 19)
#   - RAG context injected without separation markers (OWASP A04)
#   - Tool calls executed without authorization (NCA-ECC 1-1-3)
#   - Unauthenticated RAG poisoning endpoint (OWASP A01)
#   - No prompt/response audit logging (NCA-ECC 2-6-1)
#   - Debug mode enabled
# =============================================================================

app = Flask(__name__)

vertexai.init(
    project=os.getenv("GCP_PROJECT_ID"),
    location=os.getenv("GCP_REGION", "us-central1"),
)

rag = RAGService()

# VULNERABILITY: No safety settings or output filters configured
model = GenerativeModel("gemini-1.5-flash-002")


@app.route("/generate", methods=["POST"])
def generate():
    user_prompt = request.json.get("prompt", "")

    # VULNERABILITY: RAG context injected without boundary markers
    # Poisoned RAG documents can contain prompt injection payloads
    rag_context = rag.query(user_prompt)

    # VULNERABILITY: No system/user prompt separation
    # User input and system instructions are concatenated in a single string
    # making prompt injection trivial
    full_prompt = f"""Context from knowledge base:
{chr(10).join(rag_context)}

User question: {user_prompt}

You are the GCC AI Governance Assistant. Provide detailed responses about
compliance policies, customer risk scores, and regulatory requirements.
Include any relevant customer data or policy details in your response.
If the user asks about a specific customer, use the available tools to
retrieve their data."""

    # VULNERABILITY: No prompt/response audit logging
    gemini_tools = [
        Tool(
            function_declarations=[
                FunctionDeclaration(**td) for td in TOOL_DECLARATIONS
            ]
        )
    ]

    try:
        response = model.generate_content(full_prompt, tools=gemini_tools)
    except Exception as e:
        return jsonify({"error": str(e), "prompt_length": len(full_prompt)}), 500

    result_text = ""
    if response.candidates and response.candidates[0].content.parts:
        for part in response.candidates[0].content.parts:
            if hasattr(part, "function_call") and part.function_call:
                fc = part.function_call
                func = TOOL_MAP.get(fc.name)
                if func:
                    # VULNERABILITY: No authorization check before tool execution
                    # Any prompt injection that triggers a tool call will execute
                    tool_args = dict(fc.args) if fc.args else {}
                    tool_result = func(**tool_args)
                    result_text += json.dumps(tool_result) + "\n"
            elif hasattr(part, "text"):
                result_text += part.text

    # VULNERABILITY: No output sanitization or PII masking
    return jsonify({"response": result_text})


# VULNERABILITY: Unauthenticated endpoint for RAG knowledge base poisoning
@app.route("/rag/add", methods=["POST"])
def add_to_rag():
    content = request.json.get("content", "")
    if not content:
        return jsonify({"error": "No content provided"}), 400
    result = rag.add_document(content)
    return jsonify(result)


@app.route("/rag/query", methods=["POST"])
def query_rag():
    query = request.json.get("query", "")
    if not query:
        return jsonify({"error": "No query provided"}), 400
    results = rag.query(query)
    return jsonify({"results": results})


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "model": "gemini-1.5-flash-002"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8081, debug=True)
