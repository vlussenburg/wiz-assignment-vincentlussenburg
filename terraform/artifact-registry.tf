# ---------- Artifact Registry ----------

resource "google_artifact_registry_repository" "app" {
  location      = var.region
  repository_id = "bucket-list"
  description   = "Docker repository for bucket-list app"
  format        = "DOCKER"

  # Enable on-push vulnerability scanning (preventative security control)
  docker_config {
    immutable_tags = false
  }
}

# Enable Container Scanning API for automatic vulnerability analysis
resource "google_project_service" "container_scanning" {
  service            = "containerscanning.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "container_analysis" {
  service            = "containeranalysis.googleapis.com"
  disable_on_destroy = false
}
