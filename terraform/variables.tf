# =============================================================================
# 5C Security Lab - Terraform Variables (Single Source of Truth)
# =============================================================================

variable "project_id" {
  type        = string
  description = "GCP Project ID for lab deployment"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region for all resources"
}

variable "zone" {
  type        = string
  default     = "us-central1-a"
  description = "GCP zone for zonal resources (GKE cluster)"
}

variable "cluster_name" {
  type        = string
  default     = "vuln-gke-cluster"
  description = "Name of the GKE cluster"
}

variable "network_name" {
  type        = string
  default     = "vuln-network"
  description = "Name of the VPC network"
}

variable "subnet_name" {
  type        = string
  default     = "vuln-subnet"
  description = "Name of the VPC subnet"
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR range for the VPC subnet"
}

variable "pods_cidr" {
  type        = string
  default     = "10.1.0.0/16"
  description = "Secondary CIDR range for GKE pods"
}

variable "services_cidr" {
  type        = string
  default     = "10.2.0.0/16"
  description = "Secondary CIDR range for GKE services"
}

variable "bucket_name_prefix" {
  type        = string
  default     = "vuln-ai-governance-data"
  description = "Prefix for GCS bucket name (project ID will be appended)"
}

variable "node_sa_name" {
  type        = string
  default     = "vuln-gke-node-sa"
  description = "Name of the GKE node service account"
}

variable "app_namespace" {
  type        = string
  default     = "ai-governance"
  description = "Kubernetes namespace for the AI governance application"
}

variable "prod_namespace" {
  type        = string
  default     = "finance-prod"
  description = "Kubernetes namespace for finance production workloads"
}

variable "node_count" {
  type        = number
  default     = 2
  description = "Number of GKE nodes"
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-4"
  description = "Machine type for GKE nodes"
}
