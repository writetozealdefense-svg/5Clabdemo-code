# =============================================================================
# 5C Security Lab - Terraform Outputs
# =============================================================================

output "project_id" {
  value       = var.project_id
  description = "GCP project ID"
}

output "region" {
  value       = var.region
  description = "GCP region"
}

output "cluster_name" {
  value       = google_container_cluster.vuln_cluster.name
  description = "GKE cluster name"
}

output "cluster_endpoint" {
  value       = google_container_cluster.vuln_cluster.endpoint
  description = "GKE cluster API endpoint"
  sensitive   = true
}

output "cluster_ca_certificate" {
  value       = google_container_cluster.vuln_cluster.master_auth[0].cluster_ca_certificate
  description = "GKE cluster CA certificate"
  sensitive   = true
}

output "bucket_name" {
  value       = google_storage_bucket.vuln_data_bucket.name
  description = "GCS bucket name"
}

output "bucket_url" {
  value       = google_storage_bucket.vuln_data_bucket.url
  description = "GCS bucket URL"
}

output "node_sa_email" {
  value       = google_service_account.gke_node_sa.email
  description = "GKE node service account email"
}

output "node_sa_key" {
  value       = google_service_account_key.node_sa_key.private_key
  description = "GKE node service account key (base64-encoded JSON)"
  sensitive   = true
}

output "gke_connect_command" {
  value       = "gcloud container clusters get-credentials ${google_container_cluster.vuln_cluster.name} --zone ${var.zone} --project ${var.project_id}"
  description = "Command to configure kubectl"
}

output "network_name" {
  value       = google_compute_network.vuln_network.name
  description = "VPC network name"
}
