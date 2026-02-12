# ---------- VM Service Account ----------

resource "google_service_account" "mongo_vm" {
  account_id   = "mongo-vm-sa"
  display_name = "MongoDB VM Service Account"
}

# INTENTIONAL MISCONFIGURATION: overly permissive — VM can create/manage other VMs
resource "google_project_iam_member" "mongo_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.mongo_vm.email}"
}

# VM needs to write backups to GCS
resource "google_project_iam_member" "mongo_vm_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.mongo_vm.email}"
}
