# ---------- GKE Cluster ----------

resource "google_container_cluster" "primary" {
  name     = "wiz-gke"
  location = var.zone

  # We manage the node pool separately
  initial_node_count       = 1
  remove_default_node_pool = true

  network    = google_compute_network.main.id
  subnetwork = google_compute_subnetwork.private.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Demo convenience: allow kubectl from anywhere
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  # Control-plane audit logging (required by exercise)
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "APISERVER"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  # Detective security control: enable Workload Vulnerability Scanning
  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  deletion_protection = false
}

# ---------- Node Pool ----------

resource "google_container_node_pool" "default" {
  name     = "default-pool"
  location = var.zone
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = 1
    max_node_count = 3
  }

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    tags = ["gke-node"]
  }
}
