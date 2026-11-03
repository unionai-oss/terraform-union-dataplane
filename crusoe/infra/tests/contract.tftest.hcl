# The values half of the contract with the helm root (CONVENTIONS.md section 8): for each infra scenario, the outputs
# this root plans equal the fixture the helm tests plan against. The variables are the scenario's example
# (examples/crusoe/infra/<scenario>.tfvars). What is unknown at plan (the suffix, the cluster's ID and DNS name, the
# bucket URL, the storage key) is overridden with the fixture's own values, so the names derived from them are still
# checked. helm_values is compared as text: it is the exact string the helm root hands the chart.
mock_provider "crusoe" {}
mock_provider "random" {}

run "basic" {
  command = plan

  variables {
    allow_public_api_endpoint = true
    region                    = "us-east1-a"
    ssh_public_key            = "ssh-ed25519 AAAAexample user@example.com"
  }

  override_resource {
    target          = random_id.suffix
    override_during = plan
    values          = { hex = "abcd1234" }
  }
  override_resource {
    target          = crusoe_kubernetes_cluster.this
    override_during = plan
    values = {
      id       = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_id
      dns_name = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint
    }
  }
  override_resource {
    target          = crusoe_storage_s3_bucket.metadata
    override_during = plan
    values          = { s3_url = jsondecode(file("../helm/tests/fixtures/basic.json")).storage_endpoint }
  }
  override_resource {
    target          = crusoe_storage_s3_key.this
    override_during = plan
    values = {
      access_key_id     = jsondecode(file("../helm/tests/fixtures/basic.json")).storage_access_key_id
      secret_access_key = jsondecode(file("../helm/tests/fixtures/basic.json")).storage_secret_access_key
    }
  }

  assert {
    condition = jsonencode({
      bucket_name               = output.bucket_name
      cluster_endpoint          = output.cluster_endpoint
      cluster_id                = output.cluster_id
      cluster_name              = output.cluster_name
      helm_values               = output.helm_values
      kubeconfig_command        = output.kubeconfig_command
      location                  = output.location
      region                    = output.region
      storage_access_key_id     = output.storage_access_key_id
      storage_endpoint          = output.storage_endpoint
      storage_secret_access_key = nonsensitive(output.storage_secret_access_key)
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")))
    error_message = "The infra outputs for the basic scenario must equal ../helm/tests/fixtures/basic.json."
  }
}

run "gpu" {
  command = plan

  variables {
    allow_public_api_endpoint = true
    region                    = "us-east1-a"
    name                      = "union-gpu"
    ssh_public_key            = "ssh-ed25519 AAAAexample user@example.com"
    labels                    = { team = "example" }
    nat_gateway_enabled       = true
    worker_node_pool          = { enabled = true }
    gpu_node_pool             = { enabled = true, node_count = 2 }
  }

  override_resource {
    target          = random_id.suffix
    override_during = plan
    values          = { hex = "abcd1234" }
  }
  override_resource {
    target          = crusoe_kubernetes_cluster.this
    override_during = plan
    values = {
      id       = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_id
      dns_name = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint
    }
  }
  override_resource {
    target          = crusoe_storage_s3_bucket.metadata
    override_during = plan
    values          = { s3_url = jsondecode(file("../helm/tests/fixtures/gpu.json")).storage_endpoint }
  }
  override_resource {
    target          = crusoe_storage_s3_key.this
    override_during = plan
    values = {
      access_key_id     = jsondecode(file("../helm/tests/fixtures/gpu.json")).storage_access_key_id
      secret_access_key = jsondecode(file("../helm/tests/fixtures/gpu.json")).storage_secret_access_key
    }
  }

  assert {
    condition = jsonencode({
      bucket_name               = output.bucket_name
      cluster_endpoint          = output.cluster_endpoint
      cluster_id                = output.cluster_id
      cluster_name              = output.cluster_name
      helm_values               = output.helm_values
      kubeconfig_command        = output.kubeconfig_command
      location                  = output.location
      region                    = output.region
      storage_access_key_id     = output.storage_access_key_id
      storage_endpoint          = output.storage_endpoint
      storage_secret_access_key = nonsensitive(output.storage_secret_access_key)
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")))
    error_message = "The infra outputs for the gpu scenario must equal ../helm/tests/fixtures/gpu.json."
  }
}
