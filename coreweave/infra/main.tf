# Provider resources directly: there is no endorsed upstream module for CoreWeave (CONVENTIONS.md section 2).
# There is also no node-pool resource: CKS node pools are NodePool custom resources created through the Kubernetes
# API, so the system pool is in the helm root (../helm/dataplane.tf, ../helm/files/system-nodepool.yaml).

# No credentials in code: the provider reads COREWEAVE_API_TOKEN (CW-SECRET-...) from the environment. Object
# Storage calls use the same token.
provider "coreweave" {}

# Globally unique names (buckets, the organization access policy) carry this suffix so two copies can run side by
# side in one organization.
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  labels      = merge({ "managed-by" = "terraform", "stack" = var.name }, var.labels)
  unique_name = "${var.name}-${random_id.suffix.hex}"
}

# --- Network

resource "coreweave_networking_vpc" "this" {
  name = var.name
  zone = var.region

  host_prefixes = [
    {
      name     = "primary"
      type     = "PRIMARY"
      prefixes = [var.host_prefix]
    },
  ]

  vpc_prefixes = [
    { name = "pod cidr", value = var.pod_cidr },
    { name = "service cidr", value = var.service_cidr },
    { name = "internal lb cidr", value = var.internal_lb_cidr },
  ]
}

# --- Cluster (CKS)

# The public ingress takes no source CIDRs: per-CIDR access is the provider's kube_api_access, which CoreWeave
# support has to enable per organization, so it is not used here and the API is private unless opted in.
resource "coreweave_cks_cluster" "this" {
  name                   = var.name
  version                = var.kubernetes_version
  zone                   = var.region
  vpc_id                 = coreweave_networking_vpc.this.id
  public                 = var.allow_public_api_endpoint
  pod_cidr_name          = "pod cidr"
  service_cidr_name      = "service cidr"
  internal_lb_cidr_names = ["internal lb cidr"]
}
