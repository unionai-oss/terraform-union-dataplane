locals {
  metadata_bucket = "${var.name}-metadata-${random_id.suffix.hex}"
  fast_reg_bucket = "${var.name}-fast-reg-${random_id.suffix.hex}"

  # Union's Code Viewer reads both buckets from the browser.
  cors = {
    method          = ["HEAD", "GET"]
    response_header = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "google_storage_bucket" "metadata" {
  name                        = local.metadata_bucket
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  versioning {
    enabled = true
  }

  cors {
    origin          = var.cors_origins
    method          = local.cors.method
    response_header = local.cors.response_header
    max_age_seconds = local.cors.max_age_seconds
  }

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket" "fast_registration" {
  name                        = local.fast_reg_bucket
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  # Fast-registration code bundles are only needed until the run that uses them finishes.
  lifecycle_rule {
    condition {
      age = var.fast_registration_retention_days
    }
    action {
      type = "Delete"
    }
  }

  cors {
    origin          = var.cors_origins
    method          = local.cors.method
    response_header = local.cors.response_header
    max_age_seconds = local.cors.max_age_seconds
  }

  depends_on = [google_project_service.apis]
}

resource "google_artifact_registry_repository" "this" {
  repository_id = var.name
  location      = var.region
  format        = "DOCKER"
  description   = "Union Image Builder repository"
  labels        = local.labels

  depends_on = [google_project_service.apis]
}

# One Google service account for both the union-system (platform) and union (task) Kubernetes service
# accounts; the chart's BACKEND and WORKER roles point at it.
resource "google_service_account" "union" {
  account_id   = "${var.name}-system"
  display_name = "Union data plane service account"

  depends_on = [google_project_service.apis]
}

resource "google_service_account_iam_member" "workload_identity" {
  # One binding per Kubernetes service account that impersonates the Google service account.
  for_each = toset(["union-system", "union"])

  service_account_id = google_service_account.union.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${module.gke.identity_namespace}[${var.namespace}/${each.value}]"
}

# Per-bucket grants (the docs' alternative to a project-wide conditional binding). objectAdmin does not
# include storage.buckets.get, which the operator calls at startup, hence the two reader roles the docs name
# (legacyBucketReader in the procedure, bucketViewer in the pitfalls section).
resource "google_storage_bucket_iam_member" "metadata" {
  # Each role on each bucket is its own member resource.
  for_each = toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader", "roles/storage.bucketViewer"])

  bucket = google_storage_bucket.metadata.name
  role   = each.value
  member = "serviceAccount:${google_service_account.union.email}"
}

resource "google_storage_bucket_iam_member" "fast_registration" {
  # Same roles as the metadata bucket.
  for_each = toset(["roles/storage.objectAdmin", "roles/storage.legacyBucketReader", "roles/storage.bucketViewer"])

  bucket = google_storage_bucket.fast_registration.name
  role   = each.value
  member = "serviceAccount:${google_service_account.union.email}"
}

# Image Builder pushes and pulls images.
resource "google_artifact_registry_repository_iam_member" "writer" {
  repository = google_artifact_registry_repository.this.name
  location   = var.region
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.union.email}"
}

# Kubelet pulls task images as the node account, not the pod's Workload Identity. Scoped to this repository
# rather than the module's project-wide grant_registry_access.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  repository = google_artifact_registry_repository.this.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${module.gke.service_account}"
}

# iam.serviceAccounts.signBlob, required for Image Builder authentication. The docs grant this project-wide;
# it is scoped to the account itself here, which is enough for self-signing and needs no condition.
resource "google_service_account_iam_member" "token_creator" {
  service_account_id = google_service_account.union.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.union.email}"
}
