# ---------- GCS Backup Bucket ----------

resource "google_storage_bucket" "backups" {
  name          = "${var.project_id}-wiz-backups"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

# INTENTIONAL MISCONFIGURATION: public read on objects
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# INTENTIONAL MISCONFIGURATION: public listing
resource "google_storage_bucket_iam_member" "public_list" {
  bucket = google_storage_bucket.backups.name
  role   = "roles/storage.legacyBucketReader"
  member = "allUsers"
}
