mock_provider "nebius" {}
mock_provider "random" {}

# hex is computed, so it is unknown during plan unless overridden there.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

# id is computed, so it is unknown during plan unless overridden there; the bucket policy and the
# group membership refer to it.
override_resource {
  target          = nebius_iam_v1_group.union
  override_during = plan
  values          = { id = "group-e00test" }
}

override_resource {
  target          = nebius_iam_v1_service_account.this
  override_during = plan
  values          = { id = "serviceaccount-e00test" }
}

override_resource {
  target          = nebius_mk8s_v1_cluster.this
  override_during = plan
  values          = { id = "mk8scluster-e00test" }
}

override_resource {
  target          = nebius_registry_v1_registry.this
  override_during = plan
  values          = { id = "registry-e00test" }
}

variables {
  region    = "test-region1"
  parent_id = "project-e00test"
  tenant_id = "tenant-e00test"
  subnet_id = "vpc-subnet-e00test"

  public_endpoint_allowed_cidrs = ["203.0.113.0/24"]
}

run "defaults" {
  command = plan

  assert {
    condition     = nebius_storage_v1_bucket.metadata.name == "union-dataplane-metadata-abcd1234"
    error_message = "metadata bucket name must be <name>-metadata-<suffix>"
  }
  assert {
    condition     = nebius_storage_v1_bucket.fast_registration.name == "union-dataplane-fast-registration-abcd1234"
    error_message = "fast-registration bucket name must be <name>-fast-registration-<suffix>"
  }
  assert {
    condition     = nebius_mk8s_v1_cluster.this.name == "union-dataplane" && nebius_registry_v1_registry.this.name == "union-dataplane" && nebius_iam_v1_service_account.this.name == "union-dataplane-union"
    error_message = "cluster, registry and service account names must derive from var.name"
  }
  assert {
    condition     = nebius_storage_v1_bucket.metadata.labels["managed-by"] == "terraform" && nebius_mk8s_v1_cluster.this.labels["stack"] == "union-dataplane"
    error_message = "default labels must be applied"
  }

  assert {
    condition     = nebius_storage_v1_bucket.metadata.versioning_policy == "ENABLED"
    error_message = "the metadata bucket must be versioned"
  }
  assert {
    condition     = nebius_storage_v1_bucket.fast_registration.lifecycle_configuration.rules[0].expiration.days == 7
    error_message = "fast-registration objects must expire after 7 days by default"
  }
  assert {
    condition     = local.code_viewer_cors.rules[0].allowed_origins == ["https://*.unionai.cloud"] && local.code_viewer_cors.rules[0].allowed_methods == ["GET", "HEAD"]
    error_message = "both buckets need the Code Viewer CORS rule"
  }

  # Assertions are on the bucket resources themselves, not on the locals they are built from, so a bucket that
  # stops using the shared policy or CORS is caught.
  assert {
    condition = alltrue([
      for b in [nebius_storage_v1_bucket.metadata, nebius_storage_v1_bucket.fast_registration] :
      length(b.bucket_policy.rules) == 1 && b.bucket_policy.rules[0].group_id == "group-e00test" && toset(b.bucket_policy.rules[0].roles) == toset(["storage.editor"])
    ])
    error_message = "both buckets must grant storage.editor to the Union group and nobody else"
  }
  assert {
    condition = alltrue([
      for b in [nebius_storage_v1_bucket.metadata, nebius_storage_v1_bucket.fast_registration] :
      toset(b.cors.rules[0].allowed_origins) == toset(["https://*.unionai.cloud"]) && toset(b.cors.rules[0].allowed_methods) == toset(["GET", "HEAD"])
    ])
    error_message = "both buckets need the Code Viewer CORS rule"
  }
  assert {
    condition     = nebius_iam_v1_group.union.parent_id == "tenant-e00test" && nebius_iam_v1_group.union.name == "union-dataplane-union-storage-abcd1234"
    error_message = "the IAM group must live at tenant level and carry the random suffix (group names are tenant-unique)"
  }

  assert {
    condition     = nebius_iam_v2_access_key.this.account.service_account.id == "serviceaccount-e00test" && nebius_iam_v2_access_key.this.account.service_account.id == nebius_iam_v1_service_account.this.id
    error_message = "the access key must be issued to the Union service account"
  }
  assert {
    condition     = nebius_iam_v1_group_membership.this.member_id == "serviceaccount-e00test" && nebius_iam_v1_group_membership.this.parent_id == "group-e00test"
    error_message = "the Union service account must be the member of the Union group"
  }

  assert {
    condition     = nebius_mk8s_v1_node_group.system.fixed_node_count == 3 && nebius_mk8s_v1_node_group.system.template.resources.preset == "4vcpu-16gb"
    error_message = "system pool defaults to three 4vcpu-16gb nodes"
  }
  assert {
    condition     = length(nebius_mk8s_v1_node_group.worker) == 0 && length(nebius_mk8s_v1_node_group.gpu) == 0
    error_message = "worker and gpu pools must be absent by default"
  }
  assert {
    condition     = local.node_network[0].public_ip_address != null
    error_message = "nodes get a public address by default: it is the only egress path"
  }

  # The Kubernetes API is never open to any address by default (CONVENTIONS.md section 2).
  assert {
    condition     = nebius_mk8s_v1_cluster.this.control_plane.endpoints.public_endpoint.allowed_cidrs == tolist(["203.0.113.0/24"])
    error_message = "public_endpoint_allowed_cidrs must reach the cluster's public endpoint"
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == "union-dataplane-metadata-abcd1234" && yamldecode(output.helm_values).storage.fastRegistrationBucketName == "union-dataplane-fast-registration-abcd1234"
    error_message = "helm_values must name both buckets"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.endpoint == "https://storage.test-region1.nebius.cloud" && yamldecode(output.helm_values).storage.region == "test-region1"
    error_message = "helm_values must carry the regional endpoint"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.credentialsSecretRef.name == "storage-credentials"
    error_message = "helm_values must reference the storage-credentials secret and carry no credentials"
  }
  assert {
    condition     = output.registry_url == "cr.test-region1.nebius.cloud/e00test"
    error_message = "registry_url must drop the registry- prefix"
  }

  assert {
    condition     = yamldecode(output.helm_values).clusterName == nebius_mk8s_v1_cluster.this.name
    error_message = "clusterName must be the cluster name"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == nebius_storage_v1_bucket.metadata.name && yamldecode(output.helm_values).storage.fastRegistrationBucketName == nebius_storage_v1_bucket.fast_registration.name
    error_message = "bucketName and fastRegistrationBucketName must be the metadata and fast-registration buckets, not swapped"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.endpoint == output.storage_endpoint && yamldecode(output.helm_values).storage.region == var.region
    error_message = "storage.endpoint and storage.region must be the regional endpoint and the region"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.helm_values)), "host") && !contains(keys(yamldecode(output.helm_values)), "orgName") && !contains(keys(yamldecode(output.helm_values)), "global")
    error_message = "helm_values must leave the org and host to the helm root"
  }
}

run "labels_merge_over_defaults" {
  command = plan

  variables {
    labels = { team = "data", stack = "override" }
  }

  assert {
    condition     = nebius_registry_v1_registry.this.labels["team"] == "data" && nebius_registry_v1_registry.this.labels["stack"] == "override"
    error_message = "var.labels must be merged over the defaults"
  }
}

run "pools_optional_enabled" {
  command = plan

  variables {
    worker_node_pool = { enabled = true }
    gpu_node_pool    = { enabled = true }
  }

  assert {
    condition     = length(nebius_mk8s_v1_node_group.worker) == 1 && length(nebius_mk8s_v1_node_group.gpu) == 1
    error_message = "worker and gpu pools must be added when enabled"
  }
  assert {
    condition     = nebius_mk8s_v1_node_group.gpu[0].autoscaling.min_node_count == 0 && nebius_mk8s_v1_node_group.worker[0].autoscaling.min_node_count == 0
    error_message = "optional pools scale from zero"
  }
  assert {
    condition     = length(nebius_mk8s_v1_node_group.gpu[0].template.taints) == 1 && nebius_mk8s_v1_node_group.gpu[0].template.taints[0].key == "nvidia.com/gpu" && nebius_mk8s_v1_node_group.gpu[0].template.taints[0].value == "true" && nebius_mk8s_v1_node_group.gpu[0].template.taints[0].effect == "NO_SCHEDULE"
    error_message = "the gpu pool must carry the nvidia.com/gpu=true:NoSchedule taint"
  }
  assert {
    condition     = nebius_mk8s_v1_node_group.worker[0].template.taints == null && nebius_mk8s_v1_node_group.system.template.taints == null
    error_message = "only the gpu pool is tainted"
  }
  # Compared with the planned taint, so the two cannot drift apart. The node group spells the effect NO_SCHEDULE.
  assert {
    condition = yamldecode(output.helm_values).config.k8s.plugins.k8s["resource-tolerations"] == {
      "nvidia.com/gpu" = [for t in nebius_mk8s_v1_node_group.gpu[0].template.taints : { key = t.key, operator = "Equal", value = t.value, effect = t.effect == "NO_SCHEDULE" ? "NoSchedule" : t.effect }]
    }
    error_message = "task pods that request nvidia.com/gpu must tolerate exactly the gpu pool's taint"
  }
  assert {
    condition     = alltrue([for g in [nebius_mk8s_v1_node_group.system, nebius_mk8s_v1_node_group.worker[0], nebius_mk8s_v1_node_group.gpu[0]] : g.labels["managed-by"] == "terraform" && g.labels["stack"] == "union-dataplane"])
    error_message = "default labels must be applied to every node group"
  }
  assert {
    condition     = nebius_mk8s_v1_node_group.gpu[0].template.gpu_settings.drivers_preset == "cuda12"
    error_message = "the gpu pool must request the NVIDIA drivers preset by default"
  }
}

run "gpu_drivers_preset_opt_out" {
  command = plan

  variables {
    gpu_node_pool = { enabled = true, drivers_preset = "" }
  }

  assert {
    condition     = local.gpu_settings == null
    error_message = "an empty drivers_preset must leave the drivers to a GPU operator"
  }
}

run "api_endpoint_needs_allowed_cidrs" {
  command = plan

  variables {
    public_endpoint_allowed_cidrs = []
  }

  expect_failures = [var.public_endpoint_allowed_cidrs]
}

run "open_api_endpoint_needs_explicit_opt_in" {
  command = plan

  variables {
    public_endpoint_allowed_cidrs = []
    allow_public_api_endpoint     = true
  }

  assert {
    condition     = nebius_mk8s_v1_cluster.this.control_plane.endpoints.public_endpoint.allowed_cidrs == null
    error_message = "with allow_public_api_endpoint = true and no CIDRs the public endpoint is unrestricted"
  }
}

run "private_nodes_when_requested" {
  command = plan

  variables {
    node_public_ip = false
  }

  assert {
    condition     = local.node_network[0].public_ip_address == null
    error_message = "node_public_ip = false must not request a public address"
  }
}

run "rejects_bad_name" {
  command = plan

  variables {
    name = "Not_Valid"
  }

  expect_failures = [var.name]
}

run "rejects_small_system_pool" {
  command = plan

  variables {
    system_node_pool = { node_count = 1 }
  }

  expect_failures = [var.system_node_pool]
}
