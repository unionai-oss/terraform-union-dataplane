variable "allow_public_api_endpoint" {
  type        = bool
  description = "Allow api_allowed_cidr to be unset or a /0, which leaves the public Kubernetes API endpoint open to any address. Off by default: set api_allowed_cidr to your network instead."
  default     = false
}

variable "api_allowed_cidr" {
  type        = string
  description = "Source CIDR allowed to reach the public Kubernetes API endpoint (TCP 6443), for example your admin/CI network. Required unless allow_public_api_endpoint is true; null then means 0.0.0.0/0."
  default     = null

  validation {
    condition     = var.api_allowed_cidr == null || can(cidrhost(var.api_allowed_cidr, 0))
    error_message = "api_allowed_cidr must be a valid CIDR block, for example 203.0.113.0/24."
  }

  validation {
    # Unset and a /0 both admit the whole internet to the API, so either has to be asked for. coalesce stands in
    # for a null check because && does not short-circuit before Terraform 1.12.
    condition     = var.allow_public_api_endpoint || !endswith(coalesce(var.api_allowed_cidr, "0.0.0.0/0"), "/0")
    error_message = "Set api_allowed_cidr to the network allowed to reach the Kubernetes API (not a /0), or set allow_public_api_endpoint = true to leave the public API endpoint open to any address."
  }
}

variable "compartment_ocid" {
  type        = string
  description = "OCID of the compartment that holds the OKE cluster, buckets, registry repository and policy."
}

variable "fast_registration_retention_days" {
  type        = number
  description = "Days after which objects in the fast-registration bucket are deleted (docs suggest e.g. 7)."
  default     = 7

  validation {
    condition     = var.fast_registration_retention_days >= 1
    error_message = "fast_registration_retention_days must be at least 1."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "OKE Kubernetes version. Must be one of the three most recent minor versions OKE offers; list valid values with `oci ce cluster-options get --cluster-option-id all`."
  default     = "v1.34.1"
}

variable "labels" {
  type        = map(string)
  description = "Extra freeform tags, merged over the defaults (managed-by, stack). Keys and values should be lowercase."
  default     = {}
}

variable "name" {
  type        = string
  description = "Name prefix for the cluster, VCN, buckets, registry repository and IAM objects. Lowercase letters, digits and hyphens; a random suffix is added to every tenancy-unique name."
  default     = "union-dataplane"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 31 characters."
  }
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR of the private subnet for worker nodes and pods (VCN-native pod networking draws pod IPs from it). Sized /18 per the docs; pod-IP exhaustion is the most common scale blocker, so do not shrink it."
  default     = "10.0.0.0/18"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR of the public subnet for the Kubernetes API endpoint and load balancers."
  default     = "10.0.192.0/24"
}

variable "region" {
  type        = string
  description = "OCI region identifier, e.g. us-ashburn-1."
}

variable "static_credentials_user_ocid" {
  type        = string
  description = "Option B only: OCID of an IAM user to create an S3-compatibility customer secret key for. Leave null to use instance principals (Option A, recommended). The secret is stored in Terraform state."
  default     = null
}

variable "system_node_pool" {
  type = object({
    shape      = optional(string, "VM.Standard.E5.Flex")
    ocpus      = optional(number, 4)
    memory_gbs = optional(number, 32)
    size       = optional(number, 3)
  })
  description = "System node pool. Shape must be non-burstable. 1 OCPU = 2 vCPU, so the default 4 OCPU covers the 14 vCPU of default system requests across 3 nodes (docs minimum per node: 4 vCPU / 16 GB)."
  default     = {}
}

variable "tenancy_ocid" {
  type        = string
  description = "OCID of the tenancy. Dynamic groups can only be created in the tenancy (root compartment)."
}

variable "vcn_cidr" {
  type        = string
  description = "CIDR of the VCN."
  default     = "10.0.0.0/16"
}

variable "worker_node_pool" {
  type = object({
    enabled     = optional(bool, false)
    shape       = optional(string, "VM.Standard.E5.Flex")
    ocpus       = optional(number, 4)
    memory_gbs  = optional(number, 32)
    size        = optional(number, 1)
    preemptible = optional(bool, false)
  })
  description = "Optional dedicated worker pool. Disabled by default: task pods then run on the system pool. preemptible runs the nodes as preemptible instances, so workloads must tolerate interruption."
  default     = {}
}
