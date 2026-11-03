# The helm root's tests read this root's outputs from the fixtures in ../helm/tests/fixtures, one per scenario of
# examples/gcp/infra. This file plans this root with each scenario's inputs and requires every output to equal its
# fixture, so the helm tests cannot pass against outputs this root does not produce. checks.sh separately requires the
# fixture keys to be exactly the output names.
#
# Values that are unknown until apply (the cluster's name, endpoint, CA and node service account, and the Union service
# account's email) are overridden with the fixture's own values, so for those this checks the wiring (which attribute
# reaches which output) and not the value. The region is example-region1 rather than the examples' real region, so the
# registry path in the fixtures reads as a placeholder.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = { names = ["zone-a", "zone-b", "zone-c", "zone-d"] }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "abcd1234" }
}

# The repository's full name is computed; the IAM members take it as their target.
override_resource {
  target          = google_artifact_registry_repository.this
  override_during = plan
  values          = { name = "projects/example-project/locations/example-region1/repositories/example" }
}

# The inputs of examples/gcp/infra/basic.tfvars, against ../helm/tests/fixtures/basic.json.
run "basic" {
  command = plan

  variables {
    project_id                 = "example-project"
    region                     = "example-region1"
    master_authorized_networks = [{ cidr_block = "203.0.113.0/24", display_name = "office" }]
  }

  override_module {
    target = module.gke
    outputs = {
      ca_certificate     = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_ca_certificate
      endpoint           = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint
      identity_namespace = "example-project.svc.id.goog"
      name               = jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_name
      service_account    = jsondecode(file("../helm/tests/fixtures/basic.json")).node_service_account_email
    }
  }

  override_resource {
    target          = google_service_account.union
    override_during = plan
    values = {
      email = jsondecode(file("../helm/tests/fixtures/basic.json")).service_account_email
      name  = "projects/example-project/serviceAccounts/${jsondecode(file("../helm/tests/fixtures/basic.json")).service_account_email}"
    }
  }

  assert {
    condition     = jsonencode(output.artifact_registry_path) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).artifact_registry_path)
    error_message = "output artifact_registry_path differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.artifact_registry_repository) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).artifact_registry_repository)
    error_message = "output artifact_registry_repository differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).bucket_name)
    error_message = "output bucket_name differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.cluster_ca_certificate) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_ca_certificate)
    error_message = "output cluster_ca_certificate differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).cluster_name)
    error_message = "output cluster_name differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.fast_registration_bucket) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).fast_registration_bucket)
    error_message = "output fast_registration_bucket differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).helm_values)
    error_message = "output helm_values differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.namespace) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).namespace)
    error_message = "output namespace differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.node_service_account_email) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).node_service_account_email)
    error_message = "output node_service_account_email differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.project_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).project_id)
    error_message = "output project_id differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).region)
    error_message = "output region differs from ../helm/tests/fixtures/basic.json"
  }

  assert {
    condition     = jsonencode(output.service_account_email) == jsonencode(jsondecode(file("../helm/tests/fixtures/basic.json")).service_account_email)
    error_message = "output service_account_email differs from ../helm/tests/fixtures/basic.json"
  }
}

# The inputs of examples/gcp/infra/gpu.tfvars, against ../helm/tests/fixtures/gpu.json.
run "gpu" {
  command = plan

  variables {
    project_id                 = "example-project"
    region                     = "example-region1"
    name                       = "union-gpu"
    labels                     = { team = "example" }
    worker_node_pool           = { enabled = true, spot = true }
    gpu_node_pool              = { enabled = true }
    master_authorized_networks = [{ cidr_block = "203.0.113.0/24", display_name = "office" }]
  }

  override_module {
    target = module.gke
    outputs = {
      ca_certificate     = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_ca_certificate
      endpoint           = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint
      identity_namespace = "example-project.svc.id.goog"
      name               = jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_name
      service_account    = jsondecode(file("../helm/tests/fixtures/gpu.json")).node_service_account_email
    }
  }

  override_resource {
    target          = google_service_account.union
    override_during = plan
    values = {
      email = jsondecode(file("../helm/tests/fixtures/gpu.json")).service_account_email
      name  = "projects/example-project/serviceAccounts/${jsondecode(file("../helm/tests/fixtures/gpu.json")).service_account_email}"
    }
  }

  assert {
    condition     = jsonencode(output.artifact_registry_path) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).artifact_registry_path)
    error_message = "output artifact_registry_path differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.artifact_registry_repository) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).artifact_registry_repository)
    error_message = "output artifact_registry_repository differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).bucket_name)
    error_message = "output bucket_name differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.cluster_ca_certificate) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_ca_certificate)
    error_message = "output cluster_ca_certificate differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).cluster_name)
    error_message = "output cluster_name differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.fast_registration_bucket) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).fast_registration_bucket)
    error_message = "output fast_registration_bucket differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).helm_values)
    error_message = "output helm_values differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.namespace) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).namespace)
    error_message = "output namespace differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.node_service_account_email) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).node_service_account_email)
    error_message = "output node_service_account_email differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.project_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).project_id)
    error_message = "output project_id differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).region)
    error_message = "output region differs from ../helm/tests/fixtures/gpu.json"
  }

  assert {
    condition     = jsonencode(output.service_account_email) == jsonencode(jsondecode(file("../helm/tests/fixtures/gpu.json")).service_account_email)
    error_message = "output service_account_email differs from ../helm/tests/fixtures/gpu.json"
  }
}
