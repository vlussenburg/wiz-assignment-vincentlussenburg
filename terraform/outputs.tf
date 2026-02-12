output "mongo_vm_external_ip" {
  description = "MongoDB VM external (public) IP"
  value       = google_compute_instance.mongo.network_interface[0].access_config[0].nat_ip
}

output "mongo_vm_internal_ip" {
  description = "MongoDB VM internal IP (use in K8s env vars)"
  value       = google_compute_instance.mongo.network_interface[0].network_ip
}

output "gke_cluster_endpoint" {
  description = "GKE control-plane endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "gke_connect_command" {
  description = "gcloud command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --zone ${var.zone} --project ${var.project_id}"
}

output "backup_bucket_url" {
  description = "GCS backup bucket URL"
  value       = "gs://${google_storage_bucket.backups.name}"
}

output "artifact_registry_url" {
  description = "Artifact Registry Docker repo URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.app.repository_id}"
}
