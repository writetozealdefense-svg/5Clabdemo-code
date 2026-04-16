# =============================================================================
# 5C Security Lab - Cloud Storage Configuration
# VULNERABILITIES:
#   - Public bucket (SAMA-CSF 3.3.5)
#   - No CMEK encryption (SAMA-CSF 3.3.4)
#   - ACL-based access control (NCA-CCC 1-3)
#   - PII data uploaded without encryption
# =============================================================================

resource "google_storage_bucket" "vuln_data_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  # VULNERABILITY: ACL-based access instead of uniform bucket-level access
  uniform_bucket_level_access = false

  # Allow terraform destroy to delete non-empty bucket
  force_destroy = true

  # VULNERABILITY: No versioning - data can be silently overwritten
  versioning {
    enabled = false
  }

  # VULNERABILITY: No encryption block = Google-managed keys only (no CMEK)
  # VULNERABILITY: No retention policy
  # VULNERABILITY: No lifecycle rules

  labels = local.common_labels

  depends_on = [google_project_service.storage]
}

# VULNERABILITY: Public read access to bucket contents
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.vuln_data_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload synthetic PII data to the bucket
resource "google_storage_bucket_object" "pii_data" {
  name   = "data/sample_pii.json"
  source = "${path.module}/../ai/data/sample_pii.json"
  bucket = google_storage_bucket.vuln_data_bucket.name
}

# Upload knowledge base documents
resource "google_storage_bucket_object" "knowledge_base" {
  name   = "data/knowledge_base/financial_policies.txt"
  source = "${path.module}/../ai/data/knowledge_base/financial_policies.txt"
  bucket = google_storage_bucket.vuln_data_bucket.name
}
