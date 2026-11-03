variable "address_space" {
  type        = string
  description = "Address space of the VNet."
  default     = "10.0.0.0/16"
}

variable "allow_public_api_endpoint" {
  type        = bool
  description = "Allow api_server_authorized_ip_ranges to be empty, which leaves the public Kubernetes API endpoint open to any address (access still needs Entra ID). Off by default: list your CIDRs instead."
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "CIDRs allowed to reach the Kubernetes API (the endpoint is public, nodes are private). Required (non-empty) unless allow_public_api_endpoint is true."
  default     = []

  validation {
    # An empty list on a public endpoint admits the whole internet to the API, so it has to be asked for.
    condition     = length(var.api_server_authorized_ip_ranges) > 0 || var.allow_public_api_endpoint
    error_message = "api_server_authorized_ip_ranges must list at least one CIDR, or set allow_public_api_endpoint = true to leave the public API endpoint open to any address."
  }
}

variable "cluster_admin_principal_ids" {
  type        = list(string)
  description = "Object IDs of extra Entra users, groups or service principals granted Azure Kubernetes Service RBAC Cluster Admin. The identity running Terraform always gets it."
  default     = []
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins allowed to GET/HEAD the storage account for the Code Viewer. The docs use wildcards; Azure may need the exact UI origin, see README."
  default     = ["https://*.unionai.cloud", "https://*.union.ai"]
}

variable "dns_service_ip" {
  type        = string
  description = "Cluster DNS service IP; must be inside service_cidr."
  default     = "10.100.0.10"
}

variable "enable_key_vault" {
  type        = bool
  description = "Create an Azure Key Vault (RBAC mode) and grant the backend identity Key Vault Secrets Officer."
  default     = false
}

variable "gpu_node_pool" {
  type = object({
    enabled         = optional(bool, false)
    vm_size         = optional(string, "Standard_NC4as_T4_v3")
    os_disk_size_gb = optional(number, 200)
    max_nodes       = optional(number, 4)
  })
  description = "Optional GPU pool for task pods, tainted nvidia.com/gpu=true:NoSchedule and labelled node-pool=gpu; scales from zero."
  default     = {}
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes minor version; one of the three most recent minors AKS supports in your region (check `az aks get-versions`)."
  default     = "1.34"
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of an existing Log Analytics workspace that Container Insights already ships to. Null creates one named after var.name."
  default     = null
}

variable "name" {
  type        = string
  description = "Prefix for every resource name: 4-54 characters, lowercase letters, digits and single hyphens, starting with a letter and not ending in a hyphen."
  default     = "union-dataplane"

  validation {
    # The tightest limits among the names built from it, in either repository: the Log Analytics workspace (the name
    # itself) needs at least 4 characters; the AKS DNS prefix (the name itself) allows at most 54; the blob
    # containers (<name>-data, <name>-metadata) and the Postgres server (<name>-<8-character suffix>) allow at most
    # 63, and containers reject two hyphens in a row.
    condition     = length(var.name) >= 4 && length(var.name) <= 54 && can(regex("^[a-z]([a-z0-9]*(-[a-z0-9]+)*)?$", var.name))
    error_message = "name must be 4-54 characters: lowercase letters, digits and single hyphens, starting with a letter and not ending in a hyphen."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace the dataplane chart is installed into. The federated credentials are bound to it; Union's docs say not to change it."
  default     = "union"
}

variable "nodes_cidr" {
  type        = string
  description = "Private subnet for AKS nodes. With Azure CNI overlay only nodes consume subnet addresses; pods use pod_cidr."
  default     = "10.0.0.0/18"
}

variable "pod_cidr" {
  type        = string
  description = "Overlay pod CIDR. Pod-IP exhaustion is the most common scale blocker and cannot be resized in place, so keep it large."
  default     = "10.244.0.0/16"
}

variable "region" {
  type        = string
  description = "Azure location for all resources (for example the output of `az account list-locations`). No default: this repository hard-codes no region."
}

variable "service_cidr" {
  type        = string
  description = "Kubernetes service CIDR; must not overlap the VNet or pod CIDR."
  default     = "10.100.0.0/16"
}

variable "storage_shared_key_enabled" {
  type        = bool
  description = "Allow shared-key access to the storage account. Only needed for the optional FluentBit-to-Blob log path, which is not used here."
  default     = false
}

variable "system_node_pool" {
  type = object({
    vm_size         = optional(string, "Standard_D4s_v5")
    node_count      = optional(number, 3)
    os_disk_size_gb = optional(number, 200)
  })
  description = "System pool: fixed size, not burstable (at least 4 vCPU / 16 GB), untainted so task pods can use it. The image builder needs 50 GiB of ephemeral storage, hence the 200 GiB OS disk."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Extra tags, merged over the defaults (managed-by, stack)."
  default     = {}
}

variable "worker_namespaces" {
  type        = list(string)
  description = "Extra project-domain namespaces to federate the worker identity to (the `default` service account in each). Only needed with low_privilege: false; the docs example is [\"development\", \"staging\", \"production\"]."
  default     = []
}

variable "worker_node_pool" {
  type = object({
    enabled         = optional(bool, true)
    vm_size         = optional(string, "Standard_D8as_v5")
    os_disk_size_gb = optional(number, 200)
    max_nodes       = optional(number, 10)
  })
  description = "Dedicated CPU worker pool (labelled union.ai/node-role=worker); scales from zero. When disabled, task pods run on the system pool."
  default     = {}
}
