# =============================================================================
# 5C Security Lab - Network Configuration
# VULNERABILITIES:
#   - No VPC Flow Logs (NCA-ECC 2-6-2)
#   - Firewall allows 0.0.0.0/0 on management ports (NCA-CCC 2-2-1)
#   - Overly permissive internal rules (SAMA-CSF 3.2.4)
# =============================================================================

resource "google_compute_network" "vuln_network" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id

  depends_on = [google_project_service.compute]
}

# VULNERABILITY: No log_config block = no VPC flow logs
resource "google_compute_subnetwork" "vuln_subnet" {
  name                     = var.subnet_name
  ip_cidr_range            = var.subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vuln_network.id
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# VULNERABILITY: Allow all internal traffic (no segmentation)
resource "google_compute_firewall" "allow_all_internal" {
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.vuln_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# VULNERABILITY: SSH open to the entire internet (SAMA-CSF 3.2)
resource "google_compute_firewall" "allow_ssh_from_anywhere" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vuln_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# VULNERABILITY: NodePort range exposed to internet
resource "google_compute_firewall" "allow_nodeports" {
  name    = "${var.network_name}-allow-nodeports"
  network = google_compute_network.vuln_network.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# VULNERABILITY: Kubelet API and K8s API exposed to internet
resource "google_compute_firewall" "allow_management" {
  name    = "${var.network_name}-allow-mgmt"
  network = google_compute_network.vuln_network.name

  allow {
    protocol = "tcp"
    ports    = ["443", "6443", "8443", "10250", "10255"]
  }

  source_ranges = ["0.0.0.0/0"]
}
