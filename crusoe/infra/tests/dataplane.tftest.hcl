mock_provider "crusoe" {}
mock_provider "random" {}

# hex is computed, so it is unknown during plan unless overridden there.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

# s3_url is computed, so it is unknown during plan unless overridden there.
override_resource {
  target          = crusoe_storage_s3_bucket.metadata
  override_during = plan
  values          = { s3_url = "https://storage.example.com" }
}

variables {
  allow_public_api_endpoint = true
  region                    = "test-region1-a"
  ssh_public_key            = "ssh-ed25519 AAAAexample user@example.com"
}

run "defaults" {
  command = plan

  assert {
    condition     = crusoe_storage_s3_bucket.metadata.name == "union-dataplane-abcd1234"
    error_message = "bucket name must be <name>-<suffix>"
  }
  assert {
    condition     = crusoe_kubernetes_cluster.this.name == "union-dataplane" && crusoe_vpc_network.this.name == "union-dataplane-vpc" && crusoe_vpc_subnet.nodes.name == "union-dataplane-nodes"
    error_message = "network and cluster names must derive from var.name"
  }
  assert {
    condition     = crusoe_storage_s3_key.this.alias == "union-dataplane"
    error_message = "storage key alias must be var.name"
  }
  assert {
    condition     = crusoe_storage_s3_bucket.metadata.tags["managed-by"] == "terraform" && crusoe_storage_s3_bucket.metadata.tags["stack"] == "union-dataplane"
    error_message = "default labels must be applied to the bucket"
  }
  assert {
    condition     = crusoe_kubernetes_node_pool.system.requested_node_labels["managed-by"] == "terraform"
    error_message = "default labels must be applied to node pools"
  }
  assert {
    condition     = local.storage_region == "test-region1"
    error_message = "storage region must be the location without its zone letter"
  }

  assert {
    condition     = crusoe_kubernetes_node_pool.system.instance_count == 3 && crusoe_kubernetes_node_pool.system.type == "c1a.8x"
    error_message = "system pool defaults to three c1a.8x nodes"
  }
  assert {
    condition     = length(crusoe_kubernetes_node_pool.worker) == 0 && length(crusoe_kubernetes_node_pool.gpu) == 0
    error_message = "worker and gpu pools must be absent by default"
  }

  assert {
    condition     = crusoe_vpc_subnet.nodes.nat_gateway_enabled == false
    error_message = "the NAT gateway is in development at Crusoe and must be opt-in"
  }

  assert {
    condition     = output.location == "test-region1-a" && output.region == "test-region1"
    error_message = "location must be the zone given in var.region and region the same without its zone letter"
  }
  assert {
    condition     = crusoe_vpc_subnet.nodes.location == "test-region1-a" && crusoe_kubernetes_cluster.this.location == "test-region1-a" && crusoe_storage_s3_bucket.metadata.location == "test-region1-a"
    error_message = "network, cluster and bucket must all be placed in var.region"
  }

  # The helm root's storage values are these outputs.
  assert {
    condition     = output.storage_endpoint == crusoe_storage_s3_bucket.metadata.s3_url && output.bucket_name == crusoe_storage_s3_bucket.metadata.name
    error_message = "storage_endpoint and bucket_name must be the bucket's URL and name"
  }
  assert {
    condition     = output.cluster_name == crusoe_kubernetes_cluster.this.name
    error_message = "cluster_name must be the cluster's name"
  }

  assert {
    condition     = yamldecode(output.helm_values).clusterName == crusoe_kubernetes_cluster.this.name
    error_message = "clusterName must be the cluster name"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == crusoe_storage_s3_bucket.metadata.name && yamldecode(output.helm_values).storage.fastRegistrationBucketName == crusoe_storage_s3_bucket.metadata.name
    error_message = "bucketName and fastRegistrationBucketName must be the bucket"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.endpoint == crusoe_storage_s3_bucket.metadata.s3_url && yamldecode(output.helm_values).storage.region == output.region
    error_message = "storage.endpoint and storage.region must be the bucket URL and the region"
  }
  assert {
    condition     = yamldecode(output.helm_values).config.k8s.plugins.k8s["default-env-vars"][0].AWS_DEFAULT_REGION == output.region
    error_message = "AWS_DEFAULT_REGION must be the region"
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == "union-dataplane-abcd1234" && yamldecode(output.helm_values).storage.fastRegistrationBucketName == "union-dataplane-abcd1234"
    error_message = "helm_values must use the single bucket for both names"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.region == "test-region1" && yamldecode(output.helm_values).clusterName == "union-dataplane"
    error_message = "helm_values must carry the storage region and cluster name"
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.credentialsSecretRef.name == "storage-credentials"
    error_message = "helm_values must reference the storage-credentials secret and carry no credentials"
  }
  # The storage-credentials Secret the helm root creates must have the name and keys fluent-bit reads
  # (../helm/tests/dataplane.tftest.hcl checks the Secret against these values).
  assert {
    condition = yamldecode(output.helm_values).fluentbit.env == [
      { name = "AWS_ACCESS_KEY_ID", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "access_key_id" } } },
      { name = "AWS_SECRET_ACCESS_KEY", valueFrom = { secretKeyRef = { name = "storage-credentials", key = "secret_key" } } },
    ]
    error_message = "fluent-bit must take the key ID from access_key_id and the secret from secret_key."
  }
}

run "labels_merge_over_defaults" {
  command = plan

  variables {
    labels = { team = "data", stack = "override" }
  }

  assert {
    condition     = crusoe_storage_s3_bucket.metadata.tags["team"] == "data" && crusoe_storage_s3_bucket.metadata.tags["stack"] == "override"
    error_message = "var.labels must be merged over the defaults"
  }
}

run "pools_optional_enabled" {
  command = plan

  variables {
    worker_node_pool = { enabled = true }
    gpu_node_pool    = { enabled = true, node_count = 2 }
  }

  assert {
    condition     = length(crusoe_kubernetes_node_pool.worker) == 1 && length(crusoe_kubernetes_node_pool.gpu) == 1
    error_message = "worker and gpu pools must be added when enabled"
  }
  assert {
    condition     = crusoe_kubernetes_node_pool.gpu[0].instance_count == 2
    error_message = "gpu pool must use its node_count"
  }
  assert {
    condition     = length(crusoe_kubernetes_node_pool.gpu[0].node_taints) == 1 && one(crusoe_kubernetes_node_pool.gpu[0].node_taints).key == "nvidia.com/gpu" && one(crusoe_kubernetes_node_pool.gpu[0].node_taints).value == "true" && one(crusoe_kubernetes_node_pool.gpu[0].node_taints).effect == "NoSchedule"
    error_message = "the gpu pool must carry the nvidia.com/gpu=true:NoSchedule taint"
  }
  assert {
    condition     = length(crusoe_kubernetes_node_pool.worker[0].node_taints) == 0 && length(crusoe_kubernetes_node_pool.system.node_taints) == 0
    error_message = "only the gpu pool is tainted"
  }
  # Compared with the planned taint, so the two cannot drift apart.
  assert {
    condition = yamldecode(output.helm_values).config.k8s.plugins.k8s["resource-tolerations"] == {
      "nvidia.com/gpu" = [for t in crusoe_kubernetes_node_pool.gpu[0].node_taints : { key = t.key, operator = "Equal", value = t.value, effect = t.effect }]
    }
    error_message = "task pods that request nvidia.com/gpu must tolerate exactly the gpu pool's taint"
  }
  assert {
    condition     = crusoe_kubernetes_node_pool.worker[0].requested_node_labels["managed-by"] == "terraform" && crusoe_kubernetes_node_pool.gpu[0].requested_node_labels["managed-by"] == "terraform"
    error_message = "default labels must be applied to the worker and gpu pools"
  }
}

run "nat_gateway_follows_variable" {
  command = plan

  variables {
    nat_gateway_enabled = true
  }

  assert {
    condition     = crusoe_vpc_subnet.nodes.nat_gateway_enabled == true
    error_message = "nat_gateway_enabled = true must reach the subnet"
  }
}

# The org, host and client ID are helm variables, and the key pair is in the Secret the helm root creates: none of
# them is in the cloud layer.
run "helm_values_carry_no_union_settings_or_credentials" {
  command = plan

  override_resource {
    target          = crusoe_storage_s3_key.this
    override_during = plan
    values = {
      access_key_id     = "example-access-key-id"
      secret_access_key = "example-secret-access-key"
    }
  }

  assert {
    condition     = length(setintersection(keys(yamldecode(output.helm_values)), ["host", "orgName", "global", "secrets"])) == 0
    error_message = "helm_values must leave the org, host, client ID and auth Secret settings to the helm root."
  }
  assert {
    condition     = !strcontains(output.helm_values, "example-access-key-id") && !strcontains(output.helm_values, "example-secret-access-key")
    error_message = "helm_values must carry no credentials."
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
    system_node_pool = { node_count = 2 }
  }

  expect_failures = [var.system_node_pool]
}

run "open_api_endpoint_must_be_acknowledged" {
  command = plan

  variables {
    allow_public_api_endpoint = false
  }

  expect_failures = [crusoe_kubernetes_cluster.this]
}
