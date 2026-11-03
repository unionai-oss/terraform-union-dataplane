# Credentials come from Application Default Credentials (gcloud auth application-default login,
# GOOGLE_APPLICATION_CREDENTIALS or workload identity federation); none are set here.
provider "google" {
  project = var.project_id
  region  = var.region
}

# The network module declares google-beta; configured so it targets the same project.
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# No kubernetes provider is configured here. The GKE module declares one for its kube-system ConfigMaps
# (ip-masq-agent, kube-dns stub domains and upstream nameservers), but each is behind an input this root leaves at its
# default (configure_ip_masq, stub_domains, upstream_nameservers), so the module creates none and Terraform never
# starts the provider. Setting one of those inputs would need a provider configured from the cluster's outputs, the
# one-root pattern ../helm exists to avoid: put such objects in ../helm instead (CONVENTIONS.md section 10).

data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

# Suffix for globally unique names (buckets).
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  labels = merge({ "managed-by" = "terraform", "stack" = var.name }, var.labels)

  # Three zones give the three system nodes with one node per zone; a region with fewer zones gets all of them.
  # The default comes from a live lookup of the zones that are UP, so it can change between plans; set zones to pin it.
  zones = coalesce(var.zones, slice(data.google_compute_zones.available.names, 0, min(3, length(data.google_compute_zones.available.names))))

  # The security-relevant cluster inputs, named once because the tests replace module.gke and cannot read its inputs.
  # Private nodes keep node IPs off the internet; the API endpoint stays public but limited to the authorized networks.
  cluster_security = {
    enable_private_nodes       = true
    enable_private_endpoint    = false
    master_authorized_networks = var.master_authorized_networks
    identity_namespace         = "enabled"
  }

  # Cloud NAT for the private nodes, named once for the same reason. The static 1,024-port default exhausts on
  # connection-heavy workloads; dynamic port allocation requires endpoint-independent mapping to be off.
  nat = {
    enable_dynamic_port_allocation      = true
    enable_endpoint_independent_mapping = false
    min_ports_per_vm                    = 32
  }

  system_pool = {
    name              = "system"
    machine_type      = var.system_node_pool.machine_type
    autoscaling       = false
    node_count        = var.system_node_pool.node_count
    max_pods_per_node = 16
  }

  worker_pool = {
    name              = "worker"
    machine_type      = var.worker_node_pool.machine_type
    min_count         = 0
    max_count         = var.worker_node_pool.max_nodes_per_zone
    disk_size_gb      = var.worker_node_pool.disk_size_gb
    spot              = var.worker_node_pool.spot
    max_pods_per_node = 32
  }

  gpu_pool = {
    name               = "gpu"
    machine_type       = var.gpu_node_pool.machine_type
    accelerator_type   = var.gpu_node_pool.accelerator_type
    accelerator_count  = var.gpu_node_pool.accelerator_count
    gpu_driver_version = "DEFAULT"
    min_count          = 0
    max_count          = var.gpu_node_pool.max_nodes_per_zone
    disk_size_gb       = var.gpu_node_pool.disk_size_gb
    spot               = var.gpu_node_pool.spot
    max_pods_per_node  = 16
  }

  # Image Builder (BuildKit) needs 4 CPU and 50Gi ephemeral storage, more than a system node has free.
  buildkit_pool = {
    name         = "buildkit-pool"
    machine_type = var.buildkit_node_pool.machine_type
    min_count    = 0
    max_count    = var.buildkit_node_pool.max_nodes_per_zone
    disk_size_gb = var.buildkit_node_pool.disk_size_gb
  }

  # Optional pools are included only when enabled; the system pool is always present.
  node_pools = concat(
    [local.system_pool],
    var.worker_node_pool.enabled ? [local.worker_pool] : [],
    var.gpu_node_pool.enabled ? [local.gpu_pool] : [],
    var.buildkit_node_pool.enabled ? [local.buildkit_pool] : [],
  )
}

resource "google_project_service" "apis" {
  # One resource per API the base and the product layer call.
  for_each = toset([
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source  = "terraform-google-modules/network/google"
  version = "18.3.1"

  project_id   = var.project_id
  network_name = var.name

  subnets = [{
    subnet_name           = "${var.name}-nodes"
    subnet_ip             = var.nodes_cidr
    subnet_region         = var.region
    subnet_private_access = true
  }]

  secondary_ranges = {
    "${var.name}-nodes" = [
      { range_name = "pods", ip_cidr_range = var.pods_cidr },
      { range_name = "services", ip_cidr_range = var.services_cidr },
    ]
  }

  # The Compute API must be on before the first VPC call.
  depends_on = [google_project_service.apis]
}

# The network module has no NAT; private nodes reach the internet through Cloud NAT from the sibling module of
# the same family.
module "router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "9.1.0"

  project_id = var.project_id
  name       = "${var.name}-router"
  region     = var.region
  network    = module.network.network_name

  nats = [{
    name                               = "${var.name}-nat"
    nat_ip_allocate_option             = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

    enable_dynamic_port_allocation      = local.nat.enable_dynamic_port_allocation
    enable_endpoint_independent_mapping = local.nat.enable_endpoint_independent_mapping
    min_ports_per_vm                    = local.nat.min_ports_per_vm

    # Errors only: the default logs every connection.
    log_config = { enable = true, filter = "ERRORS_ONLY" }

    subnetworks = [{
      name                    = module.network.subnets_ids[0]
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }]
  }]
}

module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "47.0.0"

  project_id        = var.project_id
  name              = var.name
  region            = var.region
  zones             = local.zones
  network           = module.network.network_name
  subnetwork        = module.network.subnets_names[0]
  ip_range_pods     = "pods"
  ip_range_services = "services"

  kubernetes_version  = var.kubernetes_version
  release_channel     = "REGULAR"
  deletion_protection = var.deletion_protection

  enable_private_nodes       = local.cluster_security.enable_private_nodes
  enable_private_endpoint    = local.cluster_security.enable_private_endpoint
  master_ipv4_cidr_block     = var.master_ipv4_cidr_block
  master_authorized_networks = local.cluster_security.master_authorized_networks

  # Cluster-wide, fixed at creation; 32 matches the worker pool.
  default_max_pods_per_node = 32

  # Workload Identity pool <project>.svc.id.goog.
  identity_namespace = local.cluster_security.identity_namespace

  # Node pools are separate resources in the module; the default one is dropped.
  remove_default_node_pool = true
  node_pools               = local.node_pools
  cluster_resource_labels  = local.labels

  # The module creates the node service account with the GKE logging and monitoring roles.
  create_service_account = true

  # NAT must exist before nodes boot, or they cannot pull their first images.
  depends_on = [module.router]
}
