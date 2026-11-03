# The helm base: how this root finds the infra root and reaches the cluster it built. It declares no cloud provider.
# The product release lives in dataplane.tf.

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

# Short-lived tokens from gke-gcloud-auth-plugin, so no cluster credential is written to plan or state and none expires
# during the chart's 15-minute wait. --use_application_default_credentials makes it use Application Default
# Credentials, the same login as the infra root's google provider, rather than gcloud's own account. The endpoint
# output is a bare IP address. Remote state drops the sensitive mark, so it is put back here.
provider "kubernetes" {
  host                   = "https://${sensitive(local.infra.cluster_endpoint)}"
  cluster_ca_certificate = base64decode(sensitive(local.infra.cluster_ca_certificate))

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
    args        = ["--use_application_default_credentials"]
  }
}

provider "helm" {
  kubernetes = {
    host                   = "https://${sensitive(local.infra.cluster_endpoint)}"
    cluster_ca_certificate = base64decode(sensitive(local.infra.cluster_ca_certificate))

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "gke-gcloud-auth-plugin"
      args        = ["--use_application_default_credentials"]
    }
  }
}

# No NVIDIA device plugin here, unlike the aws and azure helm bases: GKE installs the driver (the GPU pool's
# gpu_driver_version in ../infra/main.tf) and runs the device plugin itself on GPU nodes.
