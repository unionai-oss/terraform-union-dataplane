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
  description = "Client ID of the data plane's Union client credentials (global.AUTH_CLIENT_ID), issued when you register the cluster with Union. Its secret is not an input: it goes in the union-secret-auth Kubernetes Secret (README, Apply)."

  validation {
    condition     = trimspace(var.union_client_id) != ""
    error_message = "union_client_id must not be empty: copy the client ID Union issued for this data plane."
  }
}

variable "union_control_plane_host" {
  type        = string
  description = "Union control plane hostname, no scheme or port (global.CONTROLPLANE_HOST). Copy it from your Union console or the Union deploy documentation; it is not derived from the org name."

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
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.union_org_name))
    error_message = "union_org_name must be lowercase letters, digits and hyphens, starting and ending with a letter or digit."
  }
}
