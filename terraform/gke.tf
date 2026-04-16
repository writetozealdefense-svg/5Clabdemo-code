# =============================================================================
# 5C Security Lab - GKE Cluster Configuration
# VULNERABILITIES:
#   - Legacy ABAC enabled (NCA-CCC 2-1)
#   - Legacy metadata endpoints enabled (NCA-CCC 2-1-4)
#   - Workload Identity disabled (SAMA-CSF 3.2.2)
#   - Logging and monitoring disabled (NCA-ECC 2-6-1)
#   - Public master endpoint (NCA-ECC 2-4)
#   - Network policy disabled (NCA-ECC 2-2-1)
#   - Binary authorization disabled (NCA-ECC 2-3-3)
# =============================================================================

resource "google_container_cluster" "vuln_cluster" {
  provider = google-beta

  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  network    = google_compute_network.vuln_network.name
  subnetwork = google_compute_subnetwork.vuln_subnet.name

  # Use a separately managed node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  # VULNERABILITY: Legacy ABAC enabled - bypasses RBAC
  enable_legacy_abac = true

  # VULNERABILITY: Logging and monitoring completely disabled
  logging_service    = "none"
  monitoring_service = "none"

  # VULNERABILITY: No master authorized networks - public endpoint
  # (Omitting master_authorized_networks_config block entirely)

  # VULNERABILITY: Network policy enforcement disabled
  network_policy {
    enabled = false
  }

  # VULNERABILITY: No Binary Authorization
  # (Omitting binary_authorization block)

  # VULNERABILITY: Workload Identity disabled - pods use node SA
  # (Omitting workload_identity_config block)

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Allow terraform destroy
  deletion_protection = false

  resource_labels = local.common_labels

  depends_on = [
    google_project_service.container,
    google_compute_subnetwork.vuln_subnet,
  ]
}

resource "google_container_node_pool" "vuln_nodes" {
  provider = google-beta

  name     = "${var.cluster_name}-node-pool"
  location = var.zone
  cluster  = google_container_cluster.vuln_cluster.name
  project  = var.project_id

  node_count = var.node_count

  node_config {
    machine_type = var.machine_type

    # VULNERABILITY: Over-provisioned service account on nodes
    service_account = google_service_account.gke_node_sa.email

    # VULNERABILITY: Full cloud-platform scope
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # VULNERABILITY: Legacy metadata endpoints enabled
    metadata = {
      "disable-legacy-endpoints" = "false"
    }

    image_type = "COS_CONTAINERD"

    labels = local.common_labels
  }

  management {
    auto_repair  = true
    auto_upgrade = true # GKE requires this when release_channel is set (default: REGULAR)
  }
}
