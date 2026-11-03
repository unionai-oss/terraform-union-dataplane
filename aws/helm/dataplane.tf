# The Union dataplane chart, on the buckets, registry and IRSA role the infra root created (../infra/dataplane.tf).
# The client secret the dataplane authenticates to the control plane with is a Kubernetes Secret you create before
# this apply (README: Apply), so it never reaches Terraform state.

locals {
  # The AWS keys the chart's own values.aws.yaml overlay would set, built here instead of vendoring that file: only
  # the ones this deployment needs. The cluster, bucket, account and registry keys come from the infra root's
  # helm_values.
  aws_values = {
    # The operator's cloudProvider (GPU and node handling) follows this.
    provider = "aws"
    # S3 through IRSA. The bucket names default to helm_values' METADATA_BUCKET and FAST_REGISTRATION_BUCKET, and
    # provider = "aws" also makes the image builder push to <AWS_ACCOUNT_ID>.dkr.ecr.<region>.amazonaws.com.
    storage = {
      provider = "aws"
      authType = "iam"
      region   = local.infra.region
    }
    # IRSA: the service accounts the chart creates for its own services assume the dataplane role...
    additionalServiceAccountAnnotations = { "eks.amazonaws.com/role-arn" = local.infra.iam_role_arn }
    # ...and so do the task pods' service accounts in the project namespaces (one role for both, README).
    userRoleAnnotationKey   = "eks.amazonaws.com/role-arn"
    userRoleAnnotationValue = local.infra.iam_role_arn
  }
}

resource "helm_release" "dataplane" {
  name      = "union"
  namespace = "union"
  # Idempotent: the namespace already exists when you created the auth Secret in it (README: Apply).
  create_namespace = true
  repository       = "https://unionai.github.io/helm-charts"
  chart            = "dataplane"
  version          = "2026.10.1"
  timeout          = 900

  # Later entries win, key by key.
  values = [
    # Cluster name, buckets, account, region, role ARNs and the registry, from the infra root.
    local.infra.helm_values,
    yamlencode(local.aws_values),
    yamlencode({
      global = {
        AUTH_CLIENT_ID    = var.union_client_id
        CONTROLPLANE_HOST = var.union_control_plane_host
        ORG_NAME          = var.union_org_name
      }
      # The chart reads the client secret from the Secret union-secret-auth (keys client_secret and app_secret) in
      # the release namespace, which you create; create = true would put the secret in these values and in state.
      secrets = { admin = { create = false } }
    }),
  ]
}
