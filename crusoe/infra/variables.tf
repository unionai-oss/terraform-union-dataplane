variable "allow_public_api_endpoint" {
  type        = bool
  description = "Acknowledge that the CMK Kubernetes API endpoint is public and open to any address (Kubernetes authentication still applies): the provider has no CIDR list for it. Must be true; it makes the open endpoint an explicit choice rather than a default."
  default     = false
}

variable "bucket_versioning_enabled" {
  type        = bool
  description = "Enable object versioning on the bucket. Cannot be disabled once enabled. The Crusoe docs do not require it; the general docs recommend it for the metadata bucket."
  default     = false
}

variable "gpu_node_pool" {
  type = object({
    enabled       = optional(bool, false)
    instance_type = optional(string, "h100-80gb-sxm-ib.8x")
    node_count    = optional(number, 1)
  })
  description = "Optional GPU pool for task pods. CMK node pools have a fixed node count here; this folder does not configure autoscaling."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "CMK Kubernetes minor version. Docs require one of the three most recent upstream minors; check the supported list with the Crusoe CLI before applying."
  default     = "1.35"
}

variable "labels" {
  type        = map(string)
  description = "Extra labels merged over the defaults (managed-by, stack); applied to the bucket as tags and to node pools as node labels. Keys and values lowercase."
  default     = {}
}

variable "name" {
  type        = string
  description = "Prefix for every resource name: network, subnet, cluster, bucket and storage key. Also the cluster name you register with Union."
  default     = "union-dataplane"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name))
    error_message = "name must be 3-42 lowercase letters, digits or hyphens, start with a letter and not end with a hyphen, so the suffixed bucket name stays DNS-compliant."
  }
}

variable "nat_gateway_enabled" {
  type        = bool
  description = "Create a NAT gateway on the node subnet. The Crusoe provider marks this feature as in development (contact Crusoe support to enable)."
  default     = false
}

variable "region" {
  type        = string
  description = "Crusoe location (a zone, for example us-east1-a) for the network, cluster, node pools and bucket. Must offer the chosen instance types and Cloud Storage. No default."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key installed on all node-pool VMs (required by crusoe_kubernetes_node_pool)."
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR of the node subnet. Size it for peak concurrent pods; CIDR changes on a running cluster are disruptive."
  default     = "10.0.0.0/16"
}

variable "system_node_pool" {
  type = object({
    instance_type = optional(string, "c1a.8x")
    node_count    = optional(number, 3)
  })
  description = "System pool for the operator and system pods. Docs ask for 3 non-burstable nodes of at least 4 vCPU / 16 GB; the default c1a.8x (8 vCPU / 32 GB) also covers the data plane's 14 vCPU / 27 GiB system requests across 3 nodes."
  default     = {}

  validation {
    condition     = var.system_node_pool.node_count >= 3
    error_message = "system_node_pool.node_count must be at least 3."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR of the VPC network."
  default     = "10.0.0.0/8"
}

variable "worker_node_pool" {
  type = object({
    enabled       = optional(bool, false)
    instance_type = optional(string, "c1a.8x")
    node_count    = optional(number, 1)
  })
  description = "Optional dedicated CPU pool for task pods. Disabled by default: tasks then run on the system pool. Fixed node count; no autoscaling."
  default     = {}
}
