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

# ---------- CI Binary Authorization Permissions ----------

# Read the attestor
resource "google_binary_authorization_attestor_iam_member" "ci_attestor_viewer" {
  project  = var.project_id
  attestor = google_binary_authorization_attestor.vuln_scan.name
  role     = "roles/binaryauthorization.attestorsVerifier"
  member   = "serviceAccount:${google_service_account.ci.email}"
}

# Attach occurrences to the Container Analysis note
resource "google_project_iam_member" "ci_note_attacher" {
  project = var.project_id
  role    = "roles/containeranalysis.notes.attacher"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# Create attestation occurrences
resource "google_project_iam_member" "ci_occurrence_editor" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# Sign attestations with the KMS key
resource "google_kms_crypto_key_iam_member" "ci_kms_signer" {
  crypto_key_id = google_kms_crypto_key.binauthz.id
  role          = "roles/cloudkms.signerVerifier"
  member        = "serviceAccount:${google_service_account.ci.email}"
}

# ---------- CI GKE Deploy Permissions ----------

# Get GKE credentials and deploy workloads
resource "google_project_iam_member" "ci_gke_developer" {
  project = var.project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# ---------- Terraform Service Account ----------

resource "google_service_account" "terraform" {
  account_id   = "terraform-sa"
  display_name = "Terraform CI Service Account"
}

resource "google_project_iam_member" "terraform_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Terraform needs to manage IAM bindings
resource "google_project_iam_member" "terraform_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Terraform needs to enable/disable APIs
resource "google_project_iam_member" "terraform_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Terraform needs to read KMS public keys (Binary Authorization attestor)
resource "google_project_iam_member" "terraform_kms_viewer" {
  project = var.project_id
  role    = "roles/cloudkms.viewer"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}