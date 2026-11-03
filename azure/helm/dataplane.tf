# The Union dataplane Helm release on the cluster the infra root built, with the storage, registry and identities it
# created (local.infra, main.tf).

locals {
  # The Azure layer of the chart's values. The chart ships an Azure overlay (values.azure.yaml), but it has no licence
  # file and is not vendored here; these are the keys of it this deployment needs, with values from the infra root
  # instead of chart globals. Left out: the Azure portal log links, spot-pool selectors and GPU device labels (no spot
  # pool, and the GPU pool carries no Union accelerator labels), the Key Vault secret manager (opt-in) and the DCGM
  # exporter (off in the chart).
  azure_values = {
    provider = "azure"

    # Blob storage through stow with no key: the pods authenticate with workload identity.
    storage = {
      provider   = "custom"
      bucketName = local.infra.bucket_name
      custom = {
        container = local.infra.bucket_name
        type      = "stow"
        stow = {
          kind   = "azure"
          config = { account = local.infra.storage_account_name }
        }
      }
    }

    # Workload identity: the webhook injects a federated token into pods that carry this label and run as a service
    # account annotated with an identity's client ID. The chart's own service accounts (union-system) get the backend
    # identity, task pods' service accounts the worker identity; infra federated both.
    additionalPodLabels                 = { "azure.workload.identity/use" = "true" }
    additionalServiceAccountAnnotations = { "azure.workload.identity/client-id" = local.infra.backend_client_id }
    userRoleAnnotationKey               = "azure.workload.identity/client-id"
    userRoleAnnotationValue             = local.infra.worker_client_id

    # Multi-namespace mode (low_privilege: false) only: tasks run in a namespace named after the domain, a fixed set
    # the infra root's worker_namespaces federates, because Azure federated credentials take no wildcard subject.
    # The chart passes the template through tpl, hence the backquotes.
    namespace_mapping = { template = "{{ `{{ domain }}` }}" }

    config = {
      # The abfs:// form Union's Data Lake paths need, which the chart's custom provider would otherwise give as s3://.
      operator = {
        clusterData = {
          metadataBucketPrefix = "abfs://${local.infra.bucket_name}@${local.infra.storage_account_name}.dfs.core.windows.net"
        }
      }
      k8s = {
        plugins = {
          k8s = {
            # Task pods get the workload identity label, and the storage account the SDK opens abfs:// paths with.
            default-labels   = [{ "azure.workload.identity/use" = "true" }]
            default-env-vars = [{ AZURE_STORAGE_ACCOUNT_NAME = local.infra.storage_account_name }]
          }
        }
      }
    }
  }
}

resource "helm_release" "dataplane" {
  name      = "union"
  namespace = local.infra.namespace
  # Idempotent: the namespace already exists when you created the auth Secret in it (README, Apply).
  create_namespace = true
  repository       = "https://unionai.github.io/helm-charts"
  chart            = "dataplane"
  version          = "2026.10.1"
  timeout          = 900

  # Later documents win.
  values = [
    yamlencode(local.azure_values),
    # Subscription, tenant, resource group, storage and identity globals, the cluster name, the log workspace, and
    # FluentBit off.
    local.infra.helm_values,
    yamlencode({
      global = {
        AUTH_CLIENT_ID    = var.union_client_id
        CONTROLPLANE_HOST = var.union_control_plane_host
        ORG_NAME          = var.union_org_name
      }
      # The client secret is the Kubernetes Secret union-secret-auth you create (keys client_secret and app_secret),
      # so it never reaches Terraform state.
      secrets = { admin = { create = false } }
    }),
  ]
}
