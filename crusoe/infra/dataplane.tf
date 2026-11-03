# The Union dataplane layer on top of the base in main.tf: Cloud Storage and its access key, then the cloud layer of
# the Helm values, which the helm root (../helm/dataplane.tf) passes to the chart with the Union settings.

# Single-bucket layout, as in the Crusoe values file: metadata and fast registration share one bucket.
resource "crusoe_storage_s3_bucket" "metadata" {
  name               = "${var.name}-${random_id.suffix.hex}"
  location           = var.region
  versioning_enabled = var.bucket_versioning_enabled
  tags               = local.labels
}

# The secret is stored in Terraform state (the API returns it only once), so use an encrypted remote backend. The helm
# root writes the key pair into the storage-credentials Secret the dataplane reads.
resource "crusoe_storage_s3_key" "this" {
  alias = var.name
}

locals {
  # Keys from the Crusoe deploy page. The chart ships no Crusoe overlay, so this is the whole cloud layer; the org,
  # host and client ID are helm variables. No credentials: those go in the storage-credentials Secret the helm root
  # creates, referenced by credentialsSecretRef.
  helm_values = {
    clusterName = crusoe_kubernetes_cluster.this.name
    provider    = "custom"
    storage = {
      provider                   = "compat"
      authType                   = "accesskey"
      bucketName                 = crusoe_storage_s3_bucket.metadata.name
      fastRegistrationBucketName = crusoe_storage_s3_bucket.metadata.name
      endpoint                   = crusoe_storage_s3_bucket.metadata.s3_url
      region                     = local.storage_region
      disableSSL                 = false
      credentialsSecretRef       = { name = "storage-credentials" }
    }
    config = {
      k8s = { plugins = { k8s = {
        "default-env-vars" = [{ AWS_DEFAULT_REGION = local.storage_region }]
        # Task pods that request nvidia.com/gpu tolerate the GPU pool's taint (main.tf). Crusoe documents no
        # ExtendedResourceToleration admission plugin, so Flyte's per-resource toleration adds it instead; CPU pods
        # get none and stay off the GPU nodes.
        "resource-tolerations" = {
          "nvidia.com/gpu" = [merge({ operator = "Equal" }, local.gpu_node_taint)]
        }
      } } }
    }
    operator = { enableTunnelService = true }
    fluentbit = {
      enabled = true
      env = [
        { name = "AWS_ACCESS_KEY_ID", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "access_key_id" } } },
        { name = "AWS_SECRET_ACCESS_KEY", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "secret_key" } } },
      ]
    }
  }
}
