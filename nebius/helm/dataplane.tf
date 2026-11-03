# The Union dataplane chart on the cluster from the infra root. Docs: the Nebius deploy page.

locals {
  # The release namespace. The auth Secret you create (README, Apply step 2) and the storage Secret below live in it.
  namespace = "union"

  # Null means the deploy page's default, <org>.union.ai.
  union_control_plane_host = coalesce(var.union_control_plane_host, "${var.union_org_name}.union.ai")
}

# The Object Storage access key of the infra root's service account, under the key names the chart reads.
resource "kubernetes_secret_v1" "storage_credentials" {
  metadata {
    name      = "storage-credentials" # the infra helm_values' storage.credentialsSecretRef
    namespace = local.namespace
  }

  # Remote state drops the sensitive mark, so it is put back here.
  data = {
    access_key_id = local.infra.access_key_id
    secret_key    = sensitive(local.infra.secret_access_key)
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

  # The chart ships no Nebius overlay: the infra helm_values are the whole cloud layer (storage, GPU tolerations,
  # cluster name).
  values = [
    local.infra.helm_values,
    yamlencode({
      global = {
        AUTH_CLIENT_ID    = var.union_client_id
        CONTROLPLANE_HOST = local.union_control_plane_host
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
