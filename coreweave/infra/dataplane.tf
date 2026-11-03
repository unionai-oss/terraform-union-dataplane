# The Union dataplane layer on top of the base in main.tf: AI Object Storage and its credentials. CoreWeave
# authenticates with an S3 access key, so there is no workload identity or registry to create. Then the cloud layer
# of the Helm values, which the helm root (../helm/dataplane.tf) passes to the chart with the Union settings.

locals {
  metadata_bucket = local.unique_name
  # The metadata bucket doubles as the fast-registration bucket (as on the CoreWeave deploy page) unless a
  # separate one with an expiry rule is requested.
  fast_registration_bucket = var.separate_fast_registration_bucket ? "${local.unique_name}-fast-reg" : local.metadata_bucket
  bucket_names             = distinct([local.metadata_bucket, local.fast_registration_bucket])
}

# The organization needs at least one access policy before a bucket can be created, and without one every request
# returns 403 even with valid keys. Resources are built from names, not bucket references, to keep the policy
# ahead of the buckets in the dependency graph.
resource "coreweave_object_storage_organization_access_policy" "this" {
  name = local.unique_name

  statements = [
    {
      name       = "allow-union-s3-access"
      effect     = "Allow"
      actions    = ["s3:*"]
      resources  = flatten([for b in local.bucket_names : [b, "${b}/*"]])
      principals = ["*"]
    },
  ]
}

resource "coreweave_object_storage_bucket" "metadata" {
  name = local.metadata_bucket
  zone = var.region
  tags = local.labels

  # CoreWeave rejects bucket creation until the organization has an access policy.
  depends_on = [coreweave_object_storage_organization_access_policy.this]
}

# Versioning is recommended for the metadata bucket.
resource "coreweave_object_storage_bucket_versioning" "metadata" {
  bucket = coreweave_object_storage_bucket.metadata.name

  versioning_configuration {
    status = "Enabled"
  }
}

resource "coreweave_object_storage_bucket" "fast_registration" {
  # Optional second bucket, so the expiry rule never touches the metadata bucket.
  count = var.separate_fast_registration_bucket ? 1 : 0

  name = local.fast_registration_bucket
  zone = var.region
  tags = local.labels

  # CoreWeave rejects bucket creation until the organization has an access policy.
  depends_on = [coreweave_object_storage_organization_access_policy.this]
}

# TTL on code bundles bounds cost (data-retention recommendation).
resource "coreweave_object_storage_bucket_lifecycle_configuration" "fast_registration" {
  # Only the separate bucket gets an expiry rule.
  count = var.separate_fast_registration_bucket ? 1 : 0

  bucket = coreweave_object_storage_bucket.fast_registration[0].name

  rule {
    id     = "expire-fast-registration"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.fast_registration_retention_days
    }
  }
}

# The helm root writes this key pair into the `storage-credentials` Secret the dataplane reads. The secret key lives
# in this root's state, which the helm root reads in full: protect both state backends.
resource "coreweave_object_storage_access_key" "this" {
  duration_seconds = var.access_key_duration_seconds

  # A fixed map on purpose (as in union-dataplane-tf): changing attributes replaces the key, so deriving them
  # from var.labels would rotate the credentials on any label edit, and the API rejects uppercase letters and "/"
  # that labels allow.
  attributes = { application = "union-dataplane" }

  # Without an access policy the key authenticates but every request returns 403.
  depends_on = [coreweave_object_storage_organization_access_policy.this]
}

# --- Helm values: the CoreWeave layer of the dataplane values per the CoreWeave deploy page. The chart ships no
# CoreWeave overlay, so this is the whole cloud layer; the org, host and client ID are helm variables. No
# credentials: the key pair is in the storage-credentials Secret the helm root creates.

locals {
  helm_values = yamlencode({
    clusterName = coreweave_cks_cluster.this.name
    provider    = "custom"
    storage = {
      provider                   = "custom"
      authType                   = "accesskey"
      bucketName                 = coreweave_object_storage_bucket.metadata.name
      fastRegistrationBucketName = local.fast_registration_bucket
      credentialsSecretRef       = { name = "storage-credentials" }
      custom = {
        type      = "stow"
        container = coreweave_object_storage_bucket.metadata.name
        stow = {
          kind = "s3"
          config = {
            region                   = var.region
            auth_type                = "accesskey"
            endpoint                 = "https://cwobject.com"
            disable_ssl              = false
            disable_force_path_style = true
          }
        }
      }
    }
    fluentbit = {
      enabled = true
      env = [
        { name = "AWS_ACCESS_KEY_ID", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "access_key_id" } } },
        { name = "AWS_SECRET_ACCESS_KEY", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "secret_key" } } },
      ]
    }
  })
}
