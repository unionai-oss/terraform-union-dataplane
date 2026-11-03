# The Union dataplane in the cluster the infra root built: the storage-credentials Secret and the dataplane chart.

locals {
  # The release namespace. The auth Secret you create (README, Apply step 3) and the storage Secret below live in it.
  namespace = "union"
}

# The deploy page's storage-credentials Secret, read by the chart (the infra helm_values' storage.credentialsSecretRef,
# default keys access_key_id and secret_key) and by fluent-bit.
resource "kubernetes_secret_v1" "storage_credentials" {
  metadata {
    name      = "storage-credentials" # the infra helm_values' storage.credentialsSecretRef
    namespace = local.namespace
  }

  # Remote state drops the sensitive mark, so it is put back here.
  data = {
    access_key_id = local.infra.storage_access_key_id
    secret_key    = sensitive(local.infra.storage_secret_access_key)
  }
}

# No dataplane-crds release, although the deploy page installs one: that chart is deprecated at this version, and
# with its defaults it only renders the FlyteWorkflow CRD, which this chart already installs from its crds/.
resource "helm_release" "dataplane" {
  name      = "union"
  namespace = local.namespace
  # Idempotent: the namespace already exists when you created the auth Secret in it (README, Apply step 3).
  create_namespace = true
  repository       = "https://unionai.github.io/helm-charts"
  chart            = "dataplane"
  version          = "2026.10.1"
  timeout          = 900

  # The chart ships no Crusoe overlay: the infra helm_values are the whole cloud layer (storage, GPU toleration,
  # tunnel, fluent-bit, cluster name).
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
