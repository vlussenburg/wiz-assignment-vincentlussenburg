variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "mongo_admin_user" {
  description = "MongoDB admin username"
  type        = string
  default     = "admin"
}

variable "mongo_admin_password" {
  description = "MongoDB admin password"
  type        = string
  sensitive   = true
}

variable "mongo_app_user" {
  description = "MongoDB application username"
  type        = string
  default     = "bucketlist"
}

variable "mongo_app_password" {
  description = "MongoDB application password"
  type        = string
  sensitive   = true
}
