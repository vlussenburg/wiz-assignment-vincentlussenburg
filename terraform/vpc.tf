# ---------- VPC ----------

resource "google_compute_network" "main" {
  name                    = "wiz-vpc"
  auto_create_subnetworks = false
}

# ---------- Subnets ----------

resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network       = google_compute_network.main.id
  region        = var.region
}

resource "google_compute_subnetwork" "private" {
  name          = "private-subnet"
  ip_cidr_range = "10.0.2.0/24"
  network       = google_compute_network.main.id
  region        = var.region

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.8.0.0/20"
  }
}

# ---------- Cloud Router + NAT (for GKE private nodes) ----------

resource "google_compute_router" "router" {
  name    = "wiz-router"
  network = google_compute_network.main.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "wiz-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ---------- Firewall Rules ----------

# INTENTIONAL MISCONFIGURATION: SSH open to the internet
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongo-vm"]
}

# Secure: MongoDB only from GKE pod CIDR
resource "google_compute_firewall" "allow_mongo_from_gke" {
  name    = "allow-mongo-from-gke"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  source_ranges = ["10.4.0.0/14"]
  target_tags   = ["mongo-vm"]
}

# Allow Google health-check probes to reach GKE nodes (for HTTP LB)
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks"
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["80", "8080", "443", "30000-32767"]
  }

  # Google Cloud health-check ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-node"]
}
