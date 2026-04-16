import os
import chromadb

# =============================================================================
# 5C Security Lab - RAG Service (AI Layer)
# VULNERABILITIES:
#   - No access controls on document retrieval (PDPL Art. 14)
#   - Unauthenticated document addition (RAG poisoning)
#   - No input validation on added documents
#   - No separation between system and injected content
# =============================================================================

KNOWLEDGE_BASE_DIR = os.getenv("KNOWLEDGE_BASE_DIR", "/app/data/knowledge_base")


class RAGService:
    def __init__(self):
        self.client = chromadb.Client()
        self.collection = self.client.get_or_create_collection(
            name="governance_docs",
            metadata={"hnsw:space": "cosine"},
        )
        self._load_knowledge_base()

    def _load_knowledge_base(self):
        if self.collection.count() > 0:
            return
        doc_id = 0
        if os.path.isdir(KNOWLEDGE_BASE_DIR):
            for filename in os.listdir(KNOWLEDGE_BASE_DIR):
                filepath = os.path.join(KNOWLEDGE_BASE_DIR, filename)
                if os.path.isfile(filepath):
                    with open(filepath, "r") as f:
                        content = f.read()
                    chunks = self._chunk_text(content, chunk_size=500)
                    for chunk in chunks:
                        self.collection.add(
                            documents=[chunk],
                            ids=[f"doc-{doc_id}"],
                            metadatas=[{"source": filename}],
                        )
                        doc_id += 1

    def _chunk_text(self, text, chunk_size=500):
        words = text.split()
        chunks = []
        for i in range(0, len(words), chunk_size):
            chunk = " ".join(words[i : i + chunk_size])
            if chunk.strip():
                chunks.append(chunk)
        return chunks if chunks else [text]

    # VULNERABILITY: No access controls - any query retrieves from all documents
    def query(self, query_text, n_results=3):
        if self.collection.count() == 0:
            return []
        results = self.collection.query(query_texts=[query_text], n_results=n_results)
        return results.get("documents", [[]])[0]

    # VULNERABILITY: Unauthenticated document addition allows RAG poisoning
    # An attacker can inject documents containing prompt injection payloads
    # that override system instructions when retrieved as context
    def add_document(self, content, source="user_upload"):
        doc_id = f"doc-{self.collection.count()}"
        self.collection.add(
            documents=[content],
            ids=[doc_id],
            metadatas=[{"source": source}],
        )
        return {"status": "added", "id": doc_id, "source": source}
