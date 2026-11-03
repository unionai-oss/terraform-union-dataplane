locals {
  # GKE Workload Identity: a Kubernetes service account with this annotation acts as the Google service account the
  # infra root bound to it (the union-system and union accounts in local.infra.namespace).
  workload_identity_annotation = "iam.gke.io/gcp-service-account"

  # The GCP settings the chart needs, from the infra state and this root's variables; everything else is the chart's
  # default. Chosen after the chart's own values.gcp.yaml (2026.10.1), which is not copied here: these are the keys
  # this deployment depends on. The overlay's rest (task log links, Cloud Logging as the persisted-log source, the
  # Secret Manager identity) is optional, and the persisted logs need a grant infra does not make (README: Not covered).
  dataplane_values = {
    global = {
      AUTH_CLIENT_ID    = var.union_client_id
      CONTROLPLANE_HOST = var.union_control_plane_host
      ORG_NAME          = var.union_org_name
    }
    provider = "gcp"
    # gcs makes the chart build gs:// paths (raw outputs, metadata prefix) from global.METADATA_BUCKET; the base default
    # is an S3-compatible store.
    storage = {
      provider = "gcs"
      region   = local.infra.region
      gcp      = { projectId = local.infra.project_id }
    }
    # The platform services' service accounts (operator, propeller, ...) act as the Google service account.
    additionalServiceAccountAnnotations = { (local.workload_identity_annotation) = local.infra.service_account_email }
    # Task pods' service accounts get the same annotation; the base default is the EKS IRSA one.
    userRoleAnnotationKey   = local.workload_identity_annotation
    userRoleAnnotationValue = local.infra.service_account_email
    config = {
      k8s = {
        plugins = {
          k8s = {
            # GPU tasks select nodes by GKE's accelerator labels. With the default (Flyte's EKS label, which GKE nodes
            # never carry) a GPU pod's required node affinity cannot be met and it stays Pending.
            gpu-device-node-label         = "cloud.google.com/gke-accelerator"
            gpu-partition-size-node-label = "cloud.google.com/gke-gpu-partition-size"
          }
        }
      }
    }
    # GKE's managed Cloud Logging already ships container logs (README: What it creates); the chart's fluentbit would
    # ingest them twice.
    fluentbit = { enabled = false }
    # The client secret is the Kubernetes Secret union-secret-auth you create (keys client_secret and app_secret), so
    # it never reaches Terraform state.
    secrets = { admin = { create = false } }
  }
}

resource "helm_release" "dataplane" {
  name      = "union"
  namespace = local.infra.namespace
  # Idempotent: the namespace already exists when you created the auth Secret in it (README, Apply step 2).
  create_namespace = true
  repository       = "https://unionai.github.io/helm-charts"
  chart            = "dataplane"
  version          = "2026.10.1"
  timeout          = 900

  # local.infra.helm_values carries the cluster name, buckets, service account and registry (global.*); the second
  # entry is this root's, and wins where they overlap.
  values = [
    local.infra.helm_values,
    yamlencode(local.dataplane_values),
  ]
}
