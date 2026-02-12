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

# ---------- CI Service Account ----------

resource "google_service_account" "ci" {
  account_id   = "ci-pipeline-sa"
  display_name = "CI/CD Service Account"
}

resource "google_project_iam_member" "ci_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

resource "google_project_iam_member" "ci_container_analysis_viewer" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.viewer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}
