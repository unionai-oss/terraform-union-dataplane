# Credentials come from the Nebius CLI profile (`nebius profile create`) or NEBIUS_IAM_TOKEN; none are set here.
provider "nebius" {}

# Suffix for globally unique names (the buckets).
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  labels = merge({ "managed-by" = "terraform", "stack" = var.name }, var.labels)

  # Preinstalled NVIDIA drivers. An empty preset leaves the nodes bare for a GPU operator install (null cannot mean
  # that: an optional() attribute turns an explicit null back into its default).
  gpu_settings = var.gpu_node_pool.drivers_preset == "" ? null : { drivers_preset = var.gpu_node_pool.drivers_preset }

  node_network = [{
    subnet_id = var.subnet_id
    # An empty object requests an ephemeral public address; the provider has no NAT gateway resource,
    # so a public address is the only egress path to the Union control plane.
    public_ip_address = var.node_public_ip ? {} : null
  }]
}

resource "nebius_mk8s_v1_cluster" "this" {
  parent_id = var.parent_id
  name      = var.name
  labels    = local.labels

  control_plane = {
    subnet_id = var.subnet_id
    version   = var.kubernetes_version
    endpoints = {
      public_endpoint = {
        # Nebius treats an unset or empty list as unrestricted, which variables.tf allows only with
        # allow_public_api_endpoint = true. An empty list is sent as null, as this folder always has.
        allowed_cidrs = length(var.public_endpoint_allowed_cidrs) > 0 ? var.public_endpoint_allowed_cidrs : null
      }
    }
  }
}

resource "nebius_mk8s_v1_node_group" "system" {
  parent_id        = nebius_mk8s_v1_cluster.this.id
  name             = "system"
  labels           = local.labels
  fixed_node_count = var.system_node_pool.node_count

  template = {
    resources          = { platform = var.system_node_pool.platform, preset = var.system_node_pool.preset }
    network_interfaces = local.node_network
  }
}

resource "nebius_mk8s_v1_node_group" "worker" {
  # Optional pool for CPU task pods; without it tasks run on the system pool.
  count = var.worker_node_pool.enabled ? 1 : 0

  parent_id = nebius_mk8s_v1_cluster.this.id
  name      = "worker"
  labels    = local.labels

  autoscaling = {
    min_node_count = var.worker_node_pool.min_nodes
    max_node_count = var.worker_node_pool.max_nodes
  }

  template = {
    resources          = { platform = var.worker_node_pool.platform, preset = var.worker_node_pool.preset }
    network_interfaces = local.node_network
  }
}

resource "nebius_mk8s_v1_node_group" "gpu" {
  # Optional GPU pool; GPU quota must exist beforehand.
  count = var.gpu_node_pool.enabled ? 1 : 0

  parent_id = nebius_mk8s_v1_cluster.this.id
  name      = "gpu"
  labels    = local.labels

  autoscaling = {
    min_node_count = var.gpu_node_pool.min_nodes
    max_node_count = var.gpu_node_pool.max_nodes
  }

  template = {
    resources          = { platform = var.gpu_node_pool.platform, preset = var.gpu_node_pool.preset }
    network_interfaces = local.node_network

    # Keeps CPU task pods off the expensive GPU nodes (same taint as the aws and azure GPU pools); GPU task pods
    # tolerate it through helm_values (resource-tolerations).
    taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" }]

    gpu_settings = local.gpu_settings
  }
}
