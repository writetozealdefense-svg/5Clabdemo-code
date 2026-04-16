# =============================================================================
# 5C Security Lab - Vertex AI Configuration
# VULNERABILITIES:
#   - No VPC Service Controls (SAMA-CSF 3.2)
#   - No organization policies restricting AI model access
#   - AI Platform admin granted to compute SA (iam.tf)
# =============================================================================

resource "google_project_service" "aiplatform" {
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "generativelanguage" {
  service            = "generativelanguage.googleapis.com"
  disable_on_destroy = false
}
