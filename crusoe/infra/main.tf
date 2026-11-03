# Credentials come from the Crusoe CLI config (~/.crusoe/config) or CRUSOE_ACCESS_KEY_ID / CRUSOE_SECRET_KEY,
# and the project from CRUSOE_DEFAULT_PROJECT; none are set here.
provider "crusoe" {}

# Suffix for globally unique names (the bucket).
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  labels = merge({ "managed-by" = "terraform", "stack" = var.name }, var.labels)

  # Crusoe locations are "<region>-<zone letter>"; the S3 client settings want the region.
  storage_region = replace(var.region, "/-[a-z]$/", "")

  # Keeps CPU task pods off the expensive GPU nodes (same taint as the aws and azure GPU pools). GPU task pods get
  # exactly this toleration through helm_values (dataplane.tf).
  gpu_node_taint = { key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }
}

resource "crusoe_vpc_network" "this" {
  name = "${var.name}-vpc"
  cidr = var.vpc_cidr
}

resource "crusoe_vpc_subnet" "nodes" {
  name                = "${var.name}-nodes"
  cidr                = var.subnet_cidr
  location            = var.region
  network             = crusoe_vpc_network.this.id
  nat_gateway_enabled = var.nat_gateway_enabled
}

resource "crusoe_kubernetes_cluster" "this" {
  name      = var.name
  version   = var.kubernetes_version
  location  = var.region
  subnet_id = crusoe_vpc_subnet.nodes.id

  lifecycle {
    # The CMK API endpoint is public with no CIDR list, so it is opened only on request (CONVENTIONS.md section 2).
    precondition {
      condition     = var.allow_public_api_endpoint
      error_message = "Crusoe CMK has no way to restrict its public Kubernetes API endpoint to CIDRs, so it is open to any address. Set allow_public_api_endpoint = true to accept that."
    }
  }
}

# Separate CPU pool for the operator and system pods (Crusoe docs tip).
resource "crusoe_kubernetes_node_pool" "system" {
  name                  = "system"
  cluster_id            = crusoe_kubernetes_cluster.this.id
  subnet_id             = crusoe_vpc_subnet.nodes.id
  type                  = var.system_node_pool.instance_type
  instance_count        = var.system_node_pool.node_count
  ssh_key               = var.ssh_public_key
  requested_node_labels = local.labels
}

resource "crusoe_kubernetes_node_pool" "worker" {
  # Optional pool for CPU task pods; without it tasks run on the system pool.
  count = var.worker_node_pool.enabled ? 1 : 0

  name                  = "worker"
  cluster_id            = crusoe_kubernetes_cluster.this.id
  subnet_id             = crusoe_vpc_subnet.nodes.id
  type                  = var.worker_node_pool.instance_type
  instance_count        = var.worker_node_pool.node_count
  ssh_key               = var.ssh_public_key
  requested_node_labels = local.labels
}

resource "crusoe_kubernetes_node_pool" "gpu" {
  # Optional GPU pool; tasks select it with node selectors and tolerations configured on the Union side.
  count = var.gpu_node_pool.enabled ? 1 : 0

  name                  = "gpu"
  cluster_id            = crusoe_kubernetes_cluster.this.id
  subnet_id             = crusoe_vpc_subnet.nodes.id
  type                  = var.gpu_node_pool.instance_type
  instance_count        = var.gpu_node_pool.node_count
  ssh_key               = var.ssh_public_key
  requested_node_labels = local.labels

  # local.gpu_node_taint; GPU task pods tolerate it through helm_values (resource-tolerations).
  node_taints {
    key    = local.gpu_node_taint.key
    value  = local.gpu_node_taint.value
    effect = local.gpu_node_taint.effect
  }
}
