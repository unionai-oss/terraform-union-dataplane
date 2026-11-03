variable "infra_state" {
  type = object({
    backend = optional(string, "local")
    config  = optional(any)
  })
  description = "Where the infra root keeps its state: the backend type and its settings, the same as that root's backend block. The default is the local state of ../infra, which is what a first run with no backend configured uses."
  default     = {}
}

variable "union_client_id" {
  type        = string
  description = "Client ID of the dataplane's OAuth app, from `uctl selfserve provision-dataplane-resources` (global.AUTH_CLIENT_ID). Its secret is not a variable: it goes in the Kubernetes Secret union-secret-auth you create before this apply."

  validation {
    condition     = trimspace(var.union_client_id) != ""
    error_message = "union_client_id must not be empty."
  }
}

variable "union_control_plane_host" {
  type        = string
  description = "Union control plane hostname, no scheme or port (global.CONTROLPLANE_HOST). There is no documented default for OCI, so it is required."

  validation {
    # A scheme, port or path in the host would end up verbatim in the chart values and break the tunnel.
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.union_control_plane_host))
    error_message = "union_control_plane_host must be a bare hostname: no scheme, port or path."
  }
}

variable "union_org_name" {
  type        = string
  description = "Union organization name (global.ORG_NAME)."

  validation {
    # The org name lands in the chart values as-is.
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.union_org_name))
    error_message = "union_org_name must be lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}
