# ---------- MongoDB VM ----------

data "google_compute_image" "ubuntu_2204" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_instance" "mongo" {
  name         = "mongo-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  tags = ["mongo-vm"]

  # INTENTIONAL: Ubuntu 22.04 LTS — 1+ year outdated (24.04 LTS available since Apr 2024)
  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_2204.self_link
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    # Public IP so SSH is reachable (intentional misconfiguration)
    access_config {}
  }

  # INTENTIONAL: overly-permissive service account
  service_account {
    email  = google_service_account.mongo_vm.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/mongo-startup.sh", {
    mongo_admin_user     = var.mongo_admin_user
    mongo_admin_password = var.mongo_admin_password
    mongo_app_user       = var.mongo_app_user
    mongo_app_password   = var.mongo_app_password
    backup_bucket        = google_storage_bucket.backups.name
  })

  # Prevent VM recreation when a new Ubuntu image is published
  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}
