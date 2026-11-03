variable "cluster_endpoint_private_access_cidrs" {
  type        = list(string)
  description = "CIDRs (outside the VPC, for example a peered network or VPN range) allowed to reach the private EKS API endpoint on 443. Empty adds no rule; hosts inside the VPC always reach it."
  default     = []
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Expose the EKS API endpoint publicly (restricted to cluster_endpoint_public_access_cidrs). Off by default; turn it on when Terraform or kubectl run from a host that has no route into the VPC."
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint. Required (non-empty) when cluster_endpoint_public_access is true; use your own address, not 0.0.0.0/0."
  default     = []

  validation {
    condition     = !var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "cluster_endpoint_public_access_cidrs must list at least one CIDR when cluster_endpoint_public_access is true."
  }
}

variable "fast_registration_expiration_days" {
  type        = number
  description = "Days after which fast-registration (code bundle) objects expire."
  default     = 7
}

variable "gpu_node_pool" {
  type = object({
    enabled        = optional(bool, false)
    capacity_type  = optional(string, "ON_DEMAND")
    desired_size   = optional(number, 1)
    instance_types = optional(list(string), ["g5.xlarge"])
    max_size       = optional(number, 4)
    min_size       = optional(number, 0)
  })
  description = "Optional GPU node group, tainted nvidia.com/gpu=true:NoSchedule (pods need a matching toleration). It is created with desired_size nodes (default 1), so it has a node without an autoscaler; min_size and max_size bound a cluster autoscaler or Karpenter if you install one. The EKS module ignores later changes to desired_size."
  default     = {}

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.gpu_node_pool.capacity_type)
    error_message = "gpu_node_pool.capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = 0 <= var.gpu_node_pool.min_size && var.gpu_node_pool.min_size <= var.gpu_node_pool.desired_size && var.gpu_node_pool.desired_size <= var.gpu_node_pool.max_size
    error_message = "gpu_node_pool must satisfy 0 <= min_size <= desired_size <= max_size."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Use one of the three most recent minor versions that EKS offers."
  default     = "1.34"
}

variable "name" {
  type        = string
  description = "Prefix for every resource name, and the EKS cluster name. Lowercase letters, digits and hyphens: it is part of S3 bucket names."
  default     = "union-dataplane"

  validation {
    # Letters, digits and single hyphens, starting with a letter and not ending with a hyphen (RDS identifier rules).
    condition     = can(regex("^[a-z]([a-z0-9]*(-[a-z0-9]+)*)?$", var.name))
    error_message = "name must start with a lowercase letter and contain only lowercase letters, digits and single hyphens, not ending in a hyphen."
  }

  validation {
    # The EKS module creates an IAM role with name_prefix "<name>-cluster-", which IAM caps at 38 characters.
    condition     = length(var.name) <= 29
    error_message = "name must be at most 29 characters (the EKS cluster IAM role prefix <name>-cluster- is capped at 38)."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private (node and pod) subnet CIDRs, one per AZ. Pod IPs come from these, so size generously; the default is 3x /18."
  default     = ["10.0.64.0/18", "10.0.128.0/18", "10.0.192.0/18"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs, one per AZ. Hold only NAT gateways and internet-facing load balancers."
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "region" {
  type        = string
  description = "AWS region for all resources."
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use one NAT gateway (cost-optimized) instead of one per AZ (production resilience)."
  default     = false
}

variable "system_node_pool" {
  type = object({
    instance_types = optional(list(string), ["m5.2xlarge"])
    node_count     = optional(number, 3)
  })
  description = "System node group: a fixed number of nodes. Use at least 4 vCPU / 16 GB and a non-burstable family (not t-series)."
  default     = {}

  validation {
    condition     = alltrue([for t in var.system_node_pool.instance_types : !can(regex("^t[0-9]+[a-z]*\\.", t))])
    error_message = "system_node_pool.instance_types must not be burstable t-series types."
  }

  validation {
    condition     = var.system_node_pool.node_count >= 3
    error_message = "system_node_pool.node_count must be at least 3."
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged over the defaults (managed-by, stack) and applied to every resource through the provider's default_tags."
  default     = {}
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR. CIDR blocks can be added later but subnets cannot be resized."
  default     = "10.0.0.0/16"
}

variable "worker_node_pool" {
  type = object({
    enabled        = optional(bool, false)
    capacity_type  = optional(string, "ON_DEMAND")
    desired_size   = optional(number, 1)
    instance_types = optional(list(string), ["m5.2xlarge", "m5a.2xlarge", "m6i.2xlarge"])
    max_size       = optional(number, 10)
    min_size       = optional(number, 0)
  })
  description = "Optional worker node group for task pods. It is created with desired_size nodes (default 1), so it has a node without an autoscaler; min_size and max_size bound a cluster autoscaler or Karpenter if you install one. The EKS module ignores later changes to desired_size. When disabled, task pods run on the system nodes."
  default     = {}

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.worker_node_pool.capacity_type)
    error_message = "worker_node_pool.capacity_type must be ON_DEMAND or SPOT."
  }

  validation {
    condition     = 0 <= var.worker_node_pool.min_size && var.worker_node_pool.min_size <= var.worker_node_pool.desired_size && var.worker_node_pool.desired_size <= var.worker_node_pool.max_size
    error_message = "worker_node_pool must satisfy 0 <= min_size <= desired_size <= max_size."
  }
}
