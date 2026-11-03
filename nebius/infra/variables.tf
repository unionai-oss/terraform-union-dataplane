variable "allow_public_api_endpoint" {
  type        = bool
  description = "Allow public_endpoint_allowed_cidrs to be empty, which leaves the public Kubernetes API endpoint open to any address. Off by default: list your CIDRs instead."
  default     = false
}

variable "fast_registration_retention_days" {
  type        = number
  description = "Days after which objects in the fast-registration bucket expire (docs suggest 7)."
  default     = 7
}

variable "gpu_node_pool" {
  type = object({
    enabled        = optional(bool, false)
    platform       = optional(string, "gpu-h200-sxm")
    preset         = optional(string, "8gpu-128vcpu-1600gb")
    min_nodes      = optional(number, 0)
    max_nodes      = optional(number, 2)
    drivers_preset = optional(string, "cuda12")
  })
  description = "Optional autoscaled GPU pool for task pods. GPU quota must exist beforehand; confirm the platform and preset are offered in your region. Nodes are tainted nvidia.com/gpu=true:NoSchedule. drivers_preset installs the NVIDIA drivers on the nodes (valid values depend on platform and Kubernetes version: `nebius mk8s node-group get-compatibility-matrix`); set it to an empty string to install the GPU operator yourself."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version. Must be one of the three most recent minors Nebius supports; not checked against a live tenant."
  default     = "1.34"
}

variable "labels" {
  type        = map(string)
  description = "Extra labels merged over the defaults (managed-by, stack) and applied to every resource that supports labels. Keys and values lowercase."
  default     = {}
}

variable "name" {
  type        = string
  description = "Prefix for every resource name: cluster, buckets, registry, service account and IAM group. Also the cluster name you register with Union."
  default     = "union-dataplane"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name))
    error_message = "name must be 3-32 lowercase letters, digits or hyphens, start with a letter and not end with a hyphen, so the suffixed bucket names stay DNS-compliant."
  }
}

variable "node_public_ip" {
  type        = bool
  description = "Give nodes a public IPv4 address. Nodes must reach the Union control plane and public registries, and the Nebius provider has no NAT gateway resource, so this is the egress path. Set false only if you provide egress yourself."
  default     = true
}

variable "parent_id" {
  type        = string
  description = "ID of the Nebius project (project-...) that owns every resource. Its region determines where the cluster and buckets live."
}

variable "public_endpoint_allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint. Required (non-empty) unless allow_public_api_endpoint is true: Nebius reads an empty list as unrestricted."
  default     = []

  validation {
    # An empty list on a public endpoint admits the whole internet to the API, so it has to be asked for.
    condition     = length(var.public_endpoint_allowed_cidrs) > 0 || var.allow_public_api_endpoint
    error_message = "public_endpoint_allowed_cidrs must list at least one CIDR, or set allow_public_api_endpoint = true to leave the public API endpoint open to any address."
  }
}

variable "region" {
  type        = string
  description = "Region of the project (for example eu-north1). Only used to build the Object Storage endpoint and registry URL; it must match the region of parent_id. No default."
}

variable "subnet_id" {
  type        = string
  description = "ID of an existing VPC subnet (vpc-subnet-...) for the control plane and nodes, for example the project's default subnet (`nebius vpc subnet list`). Choose a large private range up front; CIDR changes on a running cluster are disruptive."
}

variable "system_node_pool" {
  type = object({
    platform   = optional(string, "cpu-d3")
    preset     = optional(string, "4vcpu-16gb")
    node_count = optional(number, 3)
  })
  description = "System pool for the operator, proxy and executor: 3 nodes of at least 4 vCPU / 16 GB, general purpose, not burstable. Fixed size."
  default     = {}

  validation {
    condition     = var.system_node_pool.node_count >= 3
    error_message = "system_node_pool.node_count must be at least 3."
  }
}

variable "tenant_id" {
  type        = string
  description = "ID of the Nebius tenant (tenant-...). IAM groups live at tenant level; used to create the group that gets bucket access."
}

variable "worker_node_pool" {
  type = object({
    enabled   = optional(bool, false)
    platform  = optional(string, "cpu-d3")
    preset    = optional(string, "8vcpu-32gb")
    min_nodes = optional(number, 0)
    max_nodes = optional(number, 5)
  })
  description = "Optional autoscaled CPU pool for task pods. Disabled by default: tasks then run on the system pool, which the docs allow."
  default     = {}
}
