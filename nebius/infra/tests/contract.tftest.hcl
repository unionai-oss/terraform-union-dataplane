# The helm root's tests plan against tests/fixtures/*.json in ../helm, which stand in for this root's outputs. Each run
# here plans this root for one fixture's scenario (the example of the same name), with the values unknown at plan
# taken from that fixture, and checks that every output is what the fixture says (CONVENTIONS.md section 8).
mock_provider "nebius" {}
mock_provider "random" {}

# The suffix both fixtures' names carry.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

override_resource {
  target          = nebius_iam_v1_group.union
  override_during = plan
  values          = { id = "group-e00example" }
}

variables {
  region    = "eu-north1"
  parent_id = "project-e00example"
  tenant_id = "tenant-e00example"
  subnet_id = "vpc-subnet-e00example"

  public_endpoint_allowed_cidrs = ["203.0.113.0/24"]
}

run "basic" {
  command = plan

  override_resource {
    target          = nebius_mk8s_v1_cluster.this
    override_during = plan
    values = {
      id = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_id
      status = {
        control_plane = {
          auth      = { cluster_ca_certificate = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_ca_certificate }
          endpoints = { public_endpoint = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint }
        }
      }
    }
  }

  override_resource {
    target          = nebius_registry_v1_registry.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/basic.json")).registry_id }
  }

  override_resource {
    target          = nebius_iam_v1_service_account.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/basic.json")).service_account_id }
  }

  override_resource {
    target          = nebius_iam_v2_access_key.this
    override_during = plan
    values = {
      status = {
        aws_access_key_id = jsondecode(file("../helm/tests/fixtures/basic.json")).access_key_id
        secret            = jsondecode(file("../helm/tests/fixtures/basic.json")).secret_access_key
      }
    }
  }

  assert {
    condition     = jsonencode(output.access_key_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).access_key_id)
    error_message = "output access_key_id differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).bucket_name)
    error_message = "output bucket_name differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.cluster_ca_certificate) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_ca_certificate)
    error_message = "output cluster_ca_certificate differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.cluster_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_id)
    error_message = "output cluster_id differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_name)
    error_message = "output cluster_name differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.fast_registration_bucket) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).fast_registration_bucket)
    error_message = "output fast_registration_bucket differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).helm_values)
    error_message = "output helm_values differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).region)
    error_message = "output region differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.registry_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).registry_id)
    error_message = "output registry_id differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.registry_url) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).registry_url)
    error_message = "output registry_url differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.service_account_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).service_account_id)
    error_message = "output service_account_id differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(output.storage_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).storage_endpoint)
    error_message = "output storage_endpoint differs from the helm fixture basic.json."
  }
  assert {
    condition     = jsonencode(nonsensitive(output.secret_access_key)) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).secret_access_key)
    error_message = "output secret_access_key differs from the helm fixture basic.json."
  }
}

run "gpu" {
  command = plan

  variables {
    name             = "union-gpu"
    worker_node_pool = { enabled = true }
    gpu_node_pool    = { enabled = true }
  }

  override_resource {
    target          = nebius_mk8s_v1_cluster.this
    override_during = plan
    values = {
      id = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_id
      status = {
        control_plane = {
          auth      = { cluster_ca_certificate = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_ca_certificate }
          endpoints = { public_endpoint = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint }
        }
      }
    }
  }

  override_resource {
    target          = nebius_registry_v1_registry.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/gpu.json")).registry_id }
  }

  override_resource {
    target          = nebius_iam_v1_service_account.this
    override_during = plan
    values          = { id = jsondecode(file("../helm/tests/fixtures/gpu.json")).service_account_id }
  }

  override_resource {
    target          = nebius_iam_v2_access_key.this
    override_during = plan
    values = {
      status = {
        aws_access_key_id = jsondecode(file("../helm/tests/fixtures/gpu.json")).access_key_id
        secret            = jsondecode(file("../helm/tests/fixtures/gpu.json")).secret_access_key
      }
    }
  }

  assert {
    condition     = jsonencode(output.access_key_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).access_key_id)
    error_message = "output access_key_id differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).bucket_name)
    error_message = "output bucket_name differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.cluster_ca_certificate) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_ca_certificate)
    error_message = "output cluster_ca_certificate differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.cluster_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_id)
    error_message = "output cluster_id differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_name)
    error_message = "output cluster_name differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.fast_registration_bucket) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).fast_registration_bucket)
    error_message = "output fast_registration_bucket differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).helm_values)
    error_message = "output helm_values differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).region)
    error_message = "output region differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.registry_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).registry_id)
    error_message = "output registry_id differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.registry_url) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).registry_url)
    error_message = "output registry_url differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.service_account_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).service_account_id)
    error_message = "output service_account_id differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(output.storage_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).storage_endpoint)
    error_message = "output storage_endpoint differs from the helm fixture gpu.json."
  }
  assert {
    condition     = jsonencode(nonsensitive(output.secret_access_key)) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).secret_access_key)
    error_message = "output secret_access_key differs from the helm fixture gpu.json."
  }
}
