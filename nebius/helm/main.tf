# The helm base: how this root finds the infra root and the cluster. It declares no cloud provider.

# Everything this root knows about the cloud comes from the infra root's outputs. Nothing is entered by hand.
data "terraform_remote_state" "infra" {
  backend = var.infra_state.backend
  # Relative to the working directory, which is helm/ under `terraform -chdir=<cloud>/helm`.
  config = var.infra_state.config == null ? { path = "../infra/terraform.tfstate" } : var.infra_state.config
}

locals {
  # Read in one place: checks.sh requires every local.infra.<name> to be an infra output.
  infra = data.terraform_remote_state.infra.outputs

  # Short-lived tokens from the Nebius CLI (the operator's own profile, README: Prerequisites), the command the
  # kubeconfig from `nebius mk8s cluster get-credentials --external` runs; no cluster credential in state.
  exec_args = ["mk8s", "v1", "cluster", "get-token", "--format", "json"]
}

provider "kubernetes" {
  host                   = local.infra.cluster_endpoint
  cluster_ca_certificate = local.infra.cluster_ca_certificate

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "nebius"
    args        = local.exec_args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = local.infra.cluster_ca_certificate

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "nebius"
      args        = local.exec_args
    }
  }
}
