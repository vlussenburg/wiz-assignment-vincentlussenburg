# ---------- Artifact Registry ----------

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "bucket-list"
  description   = "Docker repository for bucket-list app"
  format        = "DOCKER"
}
