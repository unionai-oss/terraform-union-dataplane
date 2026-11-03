variable "allow_public_api_endpoint" {
  type        = bool
  description = "Allow master_authorized_networks to be empty, which leaves the public Kubernetes API endpoint open to any address. Off by default: list your CIDRs instead."
  default     = false
}

variable "buildkit_node_pool" {
  type = object({
    enabled            = optional(bool, true)
    machine_type       = optional(string, "e2-standard-8")
    disk_size_gb       = optional(number, 200)
    max_nodes_per_zone = optional(number, 2)
  })
  description = "BuildKit pool for Image Builder (needs 4 CPU and 50Gi ephemeral storage); scales from zero."
  default     = {}
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins allowed to GET/HEAD the buckets for the Code Viewer. Docs value is a wildcard; see README for GCS's exact-match caveat."
  default     = ["https://*.unionai.cloud"]
}

variable "deletion_protection" {
  type        = bool
  description = "Protect the GKE cluster from deletion by Terraform. Set to false before terraform destroy."
  default     = true
}

variable "fast_registration_retention_days" {
  type        = number
  description = "Delete fast-registration objects after this many days (docs example: 7)."
  default     = 7
}

variable "gpu_node_pool" {
  type = object({
    enabled            = optional(bool, false)
    machine_type       = optional(string, "g2-standard-8")
    accelerator_type   = optional(string, "nvidia-l4")
    accelerator_count  = optional(number, 1)
    disk_size_gb       = optional(number, 200)
    max_nodes_per_zone = optional(number, 2)
    spot               = optional(bool, false)
  })
  description = "Optional GPU pool for task pods; scales from zero. The accelerator must exist in every zone used (see zones)."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "GKE minimum control-plane minor version (one of the three most recent minors). The release channel may upgrade beyond it."
  default     = "1.34"
}

variable "labels" {
  type        = map(string)
  description = "Extra labels, merged over the defaults (managed-by, stack). Keys and values must be lowercase."
  default     = {}
}

variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "CIDRs allowed to reach the Kubernetes API (the endpoint is public, nodes are private). Required (non-empty) unless allow_public_api_endpoint is true."
  default     = []

  validation {
    # An empty list on a public endpoint admits the whole internet to the API, so it has to be asked for.
    condition     = length(var.master_authorized_networks) > 0 || var.allow_public_api_endpoint
    error_message = "master_authorized_networks must list at least one CIDR, or set allow_public_api_endpoint = true to leave the public API endpoint open to any address."
  }
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "Unused /28 for the private GKE control plane peering."
  default     = "172.16.0.0/28"
}

variable "name" {
  type        = string
  description = "Prefix for every resource name: cluster, VPC, buckets, registry and service account. Max 23 characters so derived service account IDs stay within GCP's 30."
  default     = "union-dataplane"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}$", var.name))
    error_message = "name must be 1-23 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace the Union Helm chart is installed into. Its union-system and union service accounts get Workload Identity here, and the helm root installs the chart into it (the namespace output)."
  default     = "union"
}

variable "nodes_cidr" {
  type        = string
  description = "Primary range of the node subnet. Docs default: /19."
  default     = "10.0.0.0/19"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary range for pods. Caps node count: /19 with 32 pods/node = 128 nodes; use a /14 up front if you expect more than a few hundred nodes. Cannot be resized later without recreating node pools."
  default     = "10.0.32.0/19"
}

variable "project_id" {
  type        = string
  description = "GCP project ID that hosts the data plane."
}

variable "region" {
  type        = string
  description = "GCP region for all resources. No default: this repository hard-codes no region."
}

variable "services_cidr" {
  type        = string
  description = "Secondary range for Kubernetes services. Docs default: /20."
  default     = "10.0.64.0/20"
}

variable "system_node_pool" {
  type = object({
    machine_type = optional(string, "e2-standard-4")
    node_count   = optional(number, 1)
  })
  description = "System pool for the operator, ingress proxy and executor. node_count is per zone; with the default three zones that is the three nodes the docs ask for."
  default     = {}

  validation {
    condition     = !can(regex("^(e2-(micro|small|medium)|f1-micro|g1-small)$", var.system_node_pool.machine_type))
    error_message = "system_node_pool.machine_type must not be a burstable (shared-core) type."
  }
}

variable "worker_node_pool" {
  type = object({
    enabled            = optional(bool, false)
    machine_type       = optional(string, "e2-standard-8")
    disk_size_gb       = optional(number, 100)
    max_nodes_per_zone = optional(number, 10)
    spot               = optional(bool, false)
  })
  description = "Optional autoscaled worker pool for task pods; scales from zero. Without it, tasks run on the system pool."
  default     = {}
}

variable "zones" {
  type        = list(string)
  description = "Zones for the cluster's nodes. Null uses the first three zones that a live lookup reports as UP in the region (so the set can change between plans); set this to pin it."
  default     = null
}
