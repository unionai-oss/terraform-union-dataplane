# Credential-free mock plans: configuration behaviour only, nothing is provisioned.
mock_provider "oci" {}
mock_provider "random" {}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "a1b2c3"
  }
}

override_data {
  target          = data.oci_identity_availability_domains.this
  override_during = plan
  values = {
    availability_domains = [{ name = "ad-1" }, { name = "ad-2" }]
  }
}

override_data {
  target          = data.oci_containerengine_node_pool_option.this
  override_during = plan
  values = {
    sources = [
      { source_name = "Oracle-Linux-8-OKE-1.34.1-100", image_id = "image-x86" },
      { source_name = "Oracle-Linux-8-aarch64-OKE-1.34.1-100", image_id = "image-arm" },
      { source_name = "Oracle-Linux-8-GPU-OKE-1.34.1-100", image_id = "image-gpu" },
    ]
  }
}

override_resource {
  target          = oci_containerengine_cluster.this
  override_during = plan
  values = {
    id        = "cluster-id"
    endpoints = [{ public_endpoint = "203.0.113.10:6443" }]
  }
}

variables {
  region           = "us-ashburn-1"
  tenancy_ocid     = "tenancy-id"
  compartment_ocid = "compartment-id"
  api_allowed_cidr = "203.0.113.0/24"
}

run "names_and_labels" {
  command = plan

  variables {
    name   = "demo"
    labels = { team = "data" }
  }

  assert {
    condition     = oci_containerengine_cluster.this.name == "demo" && oci_core_vcn.this.display_name == "demo"
    error_message = "Cluster and VCN names must derive from var.name."
  }

  assert {
    condition     = oci_objectstorage_bucket.metadata.name == "demo-a1b2c3-metadata" && oci_objectstorage_bucket.fast_registration.name == "demo-a1b2c3-fast-reg"
    error_message = "Bucket names must derive from var.name and the random suffix."
  }

  assert {
    condition     = local.labels == { "managed-by" = "terraform", "stack" = "demo", "team" = "data" } && oci_containerengine_cluster.this.freeform_tags["team"] == "data" && oci_containerengine_cluster.this.freeform_tags["managed-by"] == "terraform"
    error_message = "Default labels must be merged with var.labels."
  }

  assert {
    condition     = oci_objectstorage_bucket.metadata.freeform_tags["stack"] == "demo" && oci_core_vcn.this.freeform_tags["stack"] == "demo"
    error_message = "Every taggable resource must carry the same labels."
  }

  # The pool's own tags and the tags its nodes get are separate arguments.
  assert {
    condition     = oci_containerengine_node_pool.system.freeform_tags["team"] == "data" && oci_containerengine_node_pool.system.node_config_details[0].freeform_tags["team"] == "data"
    error_message = "The system pool and its nodes must carry the labels."
  }
}

run "worker_pool_labels" {
  command = plan

  variables {
    labels           = { team = "data" }
    worker_node_pool = { enabled = true }
  }

  assert {
    condition     = oci_containerengine_node_pool.worker[0].freeform_tags["team"] == "data" && oci_containerengine_node_pool.worker[0].node_config_details[0].freeform_tags["team"] == "data"
    error_message = "The worker pool and its nodes must carry the labels."
  }
}

run "api_endpoint_follows_api_allowed_cidr" {
  command = plan

  variables {
    api_allowed_cidr = "198.51.100.0/24"
  }

  assert {
    condition     = [for r in oci_core_security_list.public.ingress_security_rules : r.source if length(r.tcp_options) > 0] == ["198.51.100.0/24"]
    error_message = "Only api_allowed_cidr may reach the API port from outside the VCN."
  }
  assert {
    condition     = alltrue([for r in oci_core_security_list.public.ingress_security_rules : contains(["198.51.100.0/24", "10.0.0.0/16"], r.source)])
    error_message = "The public security list must admit nothing but the VCN and api_allowed_cidr."
  }
}

# The Kubernetes API is never open to any address by default (CONVENTIONS.md section 2).
run "api_endpoint_needs_api_allowed_cidr" {
  command = plan

  variables {
    api_allowed_cidr = null
  }

  expect_failures = [var.api_allowed_cidr]
}

run "api_endpoint_rejects_any_address_without_opt_in" {
  command = plan

  variables {
    api_allowed_cidr = "0.0.0.0/0"
  }

  expect_failures = [var.api_allowed_cidr]
}

run "open_api_endpoint_needs_explicit_opt_in" {
  command = plan

  variables {
    api_allowed_cidr          = null
    allow_public_api_endpoint = true
  }

  assert {
    condition     = [for r in oci_core_security_list.public.ingress_security_rules : r.source if length(r.tcp_options) > 0] == ["0.0.0.0/0"]
    error_message = "With allow_public_api_endpoint = true and no api_allowed_cidr the API port is open to any address."
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = local.node_image_id == "image-x86"
    error_message = "Node image must be the x86 non-GPU image for the cluster version."
  }

  assert {
    condition     = oci_containerengine_node_pool.system.node_config_details[0].size == 3 && oci_containerengine_node_pool.system.node_shape == "VM.Standard.E5.Flex"
    error_message = "System pool must default to three non-burstable nodes."
  }

  assert {
    # The placements themselves hold plan-unknown subnet ids, so assert on the list they are built from.
    condition     = local.availability_domains == ["ad-1", "ad-2"]
    error_message = "System pool must be placed in every availability domain."
  }

  assert {
    condition     = oci_core_subnet.private.prohibit_public_ip_on_vnic == true
    error_message = "The private subnet (nodes and pods) must prohibit public IPs."
  }

  assert {
    condition     = length(oci_containerengine_node_pool.worker) == 0
    error_message = "No worker pool expected by default."
  }
}

run "worker_pool_enabled" {
  command = plan

  variables {
    worker_node_pool = { enabled = true, size = 2 }
  }

  assert {
    condition     = length(oci_containerengine_node_pool.worker) == 1 && oci_containerengine_node_pool.worker[0].node_config_details[0].size == 2
    error_message = "Enabled worker pool must be created with the requested size."
  }
  assert {
    condition     = alltrue([for p in oci_containerengine_node_pool.worker[0].node_config_details[0].placement_configs : length(p.preemptible_node_config) == 0])
    error_message = "Worker nodes are on-demand unless preemptible is set."
  }
}

run "worker_pool_preemptible" {
  command = plan

  variables {
    worker_node_pool = { enabled = true, preemptible = true }
  }

  assert {
    condition     = alltrue([for p in oci_containerengine_node_pool.worker[0].node_config_details[0].placement_configs : one(one(p.preemptible_node_config).preemption_action).type == "TERMINATE"])
    error_message = "preemptible = true must make every placement preemptible."
  }
}

run "invalid_api_cidr_rejected" {
  command = plan

  variables {
    api_allowed_cidr = "not-a-cidr"
  }

  expect_failures = [var.api_allowed_cidr]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "Upper_Case"
  }

  expect_failures = [var.name]
}

run "invalid_retention_rejected" {
  command = plan

  variables {
    fast_registration_retention_days = 0
  }

  expect_failures = [var.fast_registration_retention_days]
}
