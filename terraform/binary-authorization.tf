# ---------- Binary Authorization ----------

# Enable the Binary Authorization API
resource "google_project_service" "binary_authorization" {
  service            = "binaryauthorization.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud KMS API
resource "google_project_service" "cloudkms" {
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

# ---------- KMS Key for Attestation Signing ----------

resource "google_kms_key_ring" "binauthz" {
  name     = "binauthz-keyring"
  location = var.region

  depends_on = [google_project_service.cloudkms]
}

resource "google_kms_crypto_key" "binauthz" {
  name     = "binauthz-key"
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm = "EC_SIGN_P256_SHA256"
  }
}

# ---------- Container Analysis Note ----------

resource "google_container_analysis_note" "vuln_scan" {
  name = "vuln-scan-note"

  attestation_authority {
    hint {
      human_readable_name = "Vulnerability scan passed"
    }
  }

  depends_on = [google_project_service.container_analysis]
}

# ---------- Attestor ----------

resource "google_binary_authorization_attestor" "vuln_scan" {
  name = "vuln-scan-attestor"

  attestation_authority_note {
    note_reference = google_container_analysis_note.vuln_scan.name

    public_keys {
      id = data.google_kms_crypto_key_version.binauthz.id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.binauthz.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.binauthz.public_key[0].algorithm
      }
    }
  }

  depends_on = [google_project_service.binary_authorization]
}

# Read the auto-created key version 1
data "google_kms_crypto_key_version" "binauthz" {
  crypto_key = google_kms_crypto_key.binauthz.id
}

# ---------- Binary Authorization Policy ----------

resource "google_binary_authorization_policy" "policy" {
  # Allow GKE system images and istio
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "k8s.gcr.io/**"
  }
  admission_whitelist_patterns {
    name_pattern = "gke.gcr.io/**"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/gke-release/*"
  }
  admission_whitelist_patterns {
    name_pattern = "registry.k8s.io/**"
  }
  global_policy_evaluation_mode = "ENABLE"

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"

    require_attestations_by = [
      google_binary_authorization_attestor.vuln_scan.name
    ]
  }

  depends_on = [google_project_service.binary_authorization]
}
