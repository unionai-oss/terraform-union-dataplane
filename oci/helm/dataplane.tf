# The Union dataplane chart on the cluster from the infra root. Docs: oci.md "Deploy".

locals {
  # The release namespace. The auth Secret you create (README, Apply step 2) and the storage Secret below live in it.
  namespace = "union"
}

# The S3-compatibility key the chart's storage client needs (infra/dataplane.tf explains why there is no
# instance-principal mode), from the infra root when it created one (Option B, static_credentials_user_ocid).
# Without one you create this Secret yourself, with the same name and keys, before this apply.
resource "kubernetes_secret_v1" "storage_credentials" {
  # Without a key the infra outputs are null, and Terraform stores no null root output, so they are absent from the
  # state rather than null: try() is the only way to read them. The body reads them only when they are there.
  count = try(local.infra.s3_access_key, null) == null ? 0 : 1

  metadata {
    name      = "storage-credentials" # the infra helm_values' storage.credentialsSecretRef
    namespace = local.namespace
  }

  # Remote state drops the sensitive mark, so it is put back here.
  data = {
    access_key_id = local.infra.s3_access_key
    secret_key    = sensitive(local.infra.s3_secret_key)
  }
}

resource "helm_release" "dataplane" {
  name      = "union"
  namespace = local.namespace
  # Idempotent: the namespace already exists when you created the auth Secret in it (README, Apply step 2).
  create_namespace = true
  repository       = "https://unionai.github.io/helm-charts"
  chart            = "dataplane"
  version          = "2026.10.1"
  timeout          = 900

  # The chart ships no OCI overlay: the infra helm_values are the whole cloud layer (storage, registry, cluster name).
  values = [
    local.infra.helm_values,
    yamlencode({
      global = {
        AUTH_CLIENT_ID    = var.union_client_id
        CONTROLPLANE_HOST = var.union_control_plane_host
        ORG_NAME          = var.union_org_name
      }
      # The client secret is the Kubernetes Secret union-secret-auth you create (keys client_secret, app_secret),
      # so it never reaches Terraform state.
      secrets = { admin = { create = false } }
    }),
  ]

  # The chart reads the storage Secret when it renders (helm lookup), so the Secret has to exist first.
  depends_on = [kubernetes_secret_v1.storage_credentials]
}
