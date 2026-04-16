# =============================================================================
# 5C Security Lab - IAM Configuration
# VULNERABILITIES:
#   - Over-provisioned service account (SAMA-CSF 3.2.1)
#   - roles/editor on node SA (NCA-ECC 1-1-3)
#   - Exported SA key stored in state (NCA-ECC 2-4-1)
# =============================================================================

resource "google_service_account" "gke_node_sa" {
  account_id   = var.node_sa_name
  display_name = "Vulnerable GKE Node Service Account"
  project      = var.project_id

  depends_on = [google_project_service.iam]
}

# VULNERABILITY: roles/editor grants broad project-wide access
resource "google_project_iam_member" "node_sa_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# VULNERABILITY: Storage admin allows reading/writing all buckets
resource "google_project_iam_member" "node_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# VULNERABILITY: AI Platform admin allows model and dataset access
resource "google_project_iam_member" "node_sa_aiplatform_admin" {
  project = var.project_id
  role    = "roles/aiplatform.admin"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# VULNERABILITY: Exporting a service account key (should use Workload Identity)
resource "google_service_account_key" "node_sa_key" {
  service_account_id = google_service_account.gke_node_sa.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}
