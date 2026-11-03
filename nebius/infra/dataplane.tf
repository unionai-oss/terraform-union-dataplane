locals {
  storage_endpoint = "https://storage.${var.region}.nebius.cloud"

  # Code Viewer CORS, per the Union code-viewer page.
  code_viewer_cors = {
    rules = [{
      allowed_methods = ["GET", "HEAD"]
      allowed_origins = ["https://*.unionai.cloud"]
      allowed_headers = ["*"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }]
  }

  # Both buckets are readable and writable only by the Union group.
  union_bucket_policy = {
    rules = [{
      group_id = nebius_iam_v1_group.union.id
      roles    = ["storage.editor"]
    }]
  }
}

resource "nebius_storage_v1_bucket" "metadata" {
  parent_id         = var.parent_id
  name              = "${var.name}-metadata-${random_id.suffix.hex}"
  labels            = local.labels
  versioning_policy = "ENABLED"
  cors              = local.code_viewer_cors
  bucket_policy     = local.union_bucket_policy
}

resource "nebius_storage_v1_bucket" "fast_registration" {
  parent_id     = var.parent_id
  name          = "${var.name}-fast-registration-${random_id.suffix.hex}"
  labels        = local.labels
  cors          = local.code_viewer_cors
  bucket_policy = local.union_bucket_policy

  lifecycle_configuration = {
    rules = [{
      id     = "expire-code-bundles"
      status = "ENABLED"
      expiration = {
        days = var.fast_registration_retention_days
      }
    }]
  }
}

resource "nebius_iam_v1_service_account" "this" {
  parent_id = var.parent_id
  name      = "${var.name}-union"
  labels    = local.labels
}

# Bucket policies grant roles to a group, so the service account joins a dedicated one.
resource "nebius_iam_v1_group" "union" {
  parent_id = var.tenant_id
  name      = "${var.name}-union-storage-${random_id.suffix.hex}" # tenant-scoped, so unique per copy
}

resource "nebius_iam_v1_group_membership" "this" {
  parent_id = nebius_iam_v1_group.union.id
  member_id = nebius_iam_v1_service_account.this.id
}

resource "nebius_iam_v2_access_key" "this" {
  parent_id = var.parent_id
  name      = "${var.name}-union"

  account = {
    service_account = { id = nebius_iam_v1_service_account.this.id }
  }
  # INLINE puts the secret in state (marked sensitive); MYSTERY_BOX would need a second read step.
  secret_delivery_mode = "INLINE"
}

resource "nebius_registry_v1_registry" "this" {
  parent_id = var.parent_id
  name      = var.name
  labels    = local.labels
}

locals {
  # Storage keys from the Nebius deploy page, without credentials: the chart reads those from the
  # storage-credentials Secret, which the helm root creates from this root's access key. The org, control plane
  # host and client ID are the helm root's.
  helm_values = {
    clusterName = nebius_mk8s_v1_cluster.this.name
    provider    = "custom"
    storage = {
      bucketName                 = nebius_storage_v1_bucket.metadata.name
      endpoint                   = local.storage_endpoint
      fastRegistrationBucketName = nebius_storage_v1_bucket.fast_registration.name
      provider                   = "compat"
      region                     = var.region
      credentialsSecretRef       = { name = "storage-credentials" }
    }
    # Task pods that request nvidia.com/gpu tolerate the GPU node group's taint (main.tf). Nebius documents no
    # ExtendedResourceToleration admission plugin, so Flyte's per-resource toleration adds it instead; CPU pods get
    # none and stay off the GPU nodes.
    config = {
      k8s = { plugins = { k8s = { "resource-tolerations" = {
        "nvidia.com/gpu" = [{ key = "nvidia.com/gpu", operator = "Equal", value = "true", effect = "NoSchedule" }]
      } } } }
    }
  }
}
