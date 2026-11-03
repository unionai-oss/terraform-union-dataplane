variable "access_key_duration_seconds" {
  type        = number
  description = "Lifetime of the object storage access key in seconds; 0 creates a permanent key."
  default     = 0
}

variable "allow_public_api_endpoint" {
  type        = bool
  description = "Make the Kubernetes API server reachable from any address through CoreWeave's public ingress (authentication still applies). Off by default: the API has no public ingress."
  default     = false
}

variable "fast_registration_retention_days" {
  type        = number
  description = "Days after which objects in the separate fast-registration bucket expire. Only used when separate_fast_registration_bucket is true."
  default     = 7

  validation {
    condition     = var.fast_registration_retention_days >= 1
    error_message = "fast_registration_retention_days must be at least 1."
  }
}

variable "host_prefix" {
  type        = string
  description = "Primary host prefix (node addresses) of the VPC."
  default     = "10.16.192.0/18"
}

variable "internal_lb_cidr" {
  type        = string
  description = "VPC prefix used for internal load balancers."
  default     = "10.32.4.0/22"
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version for the CKS cluster. Must be one of the three most recent minors that CKS offers."
  default     = "v1.35"
}

variable "labels" {
  type        = map(string)
  description = "Extra labels, merged over the defaults (managed-by, stack). Applied as bucket tags and access key attributes. Keys and values should be lowercase."
  default     = {}
}

variable "name" {
  type        = string
  description = "Name of the VPC and CKS cluster, also the Union cluster name in the Helm values (it must match the name passed to `flyte create cluster`), and the prefix of the bucket and access policy names. Lowercase letters, digits and hyphens, at most 30 characters (a CKS limit); must not start with cw- or vip- (CoreWeave reserves them for bucket names)."
  default     = "union-dataplane"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.name)) && !startswith(var.name, "cw-") && !startswith(var.name, "vip-")
    error_message = "name must be 1-30 lowercase letters, digits or hyphens, start with a letter, and not start with cw- or vip-."
  }
}

variable "pod_cidr" {
  type        = string
  description = "VPC prefix used as the pod CIDR. Pod-IP exhaustion is the most common scale blocker and CIDRs cannot be resized later, so the default is a /13."
  default     = "10.0.0.0/13"
}

variable "region" {
  type        = string
  description = "CoreWeave Availability Zone for the VPC, cluster and buckets (for example US-EAST-04A). CoreWeave calls it a zone; it is named region here to match the sibling repo and is also used as the S3 region in the Helm values."
}

variable "separate_fast_registration_bucket" {
  type        = bool
  description = "Create a second bucket for fast-registration code bundles, so a short retention rule can be applied. false (default): the metadata bucket is used for both, with no expiry, as on the CoreWeave deploy page."
  default     = false
}

variable "service_cidr" {
  type        = string
  description = "VPC prefix used as the Kubernetes service CIDR."
  default     = "10.16.0.0/22"
}
