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
}

# The Crusoe CLI writes a kubeconfig (`crusoe kubernetes clusters get-credentials`, the infra output
# kubeconfig_command), and both providers read it: KUBE_CONFIG_PATH, and KUBE_CTX for a context other than its current
# one (README: Apply). That is a credential, like AWS_PROFILE, not data passed between the applies. The provider's
# crusoe_kubeconfig would need the crusoe provider here and would write a cluster-admin key into state.
provider "kubernetes" {}

provider "helm" {}
