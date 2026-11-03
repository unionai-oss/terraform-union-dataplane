# The values half of the contract with the helm root (CONVENTIONS.md section 8): for each infra scenario, the outputs
# this root plans equal the fixture the helm tests plan against. The variables are the scenario's example
# (examples/coreweave/infra/<scenario>.tfvars). What is unknown at plan (the suffix, the cluster's ID and endpoint,
# the access key) is overridden with the fixture's own values, so the names derived from them are still checked.
# helm_values is compared as text: it is the exact string the helm root hands the chart.
mock_provider "coreweave" {}
mock_provider "random" {}

run "minimal" {
  command = plan

  variables {
    region = "US-EAST-04A"
  }

  override_resource {
    target          = random_id.suffix
    override_during = plan
    values          = { hex = "a1b2c3" }
  }
  override_resource {
    target          = coreweave_cks_cluster.this
    override_during = plan
    values = {
      id                  = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_id
      api_server_endpoint = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_endpoint
    }
  }
  override_resource {
    target          = coreweave_object_storage_access_key.this
    override_during = plan
    values = {
      id         = jsondecode(file("../helm/tests/fixtures/minimal.json")).access_key_id
      secret_key = jsondecode(file("../helm/tests/fixtures/minimal.json")).secret_key
    }
  }

  assert {
    condition = jsonencode({
      access_key_id                 = output.access_key_id
      bucket_name                   = output.bucket_name
      cluster_endpoint              = output.cluster_endpoint
      cluster_id                    = output.cluster_id
      cluster_name                  = output.cluster_name
      fast_registration_bucket_name = output.fast_registration_bucket_name
      helm_values                   = output.helm_values
      object_storage_endpoint       = output.object_storage_endpoint
      region                        = output.region
      secret_key                    = nonsensitive(output.secret_key)
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")))
    error_message = "The infra outputs for the minimal scenario must equal ../helm/tests/fixtures/minimal.json."
  }
}

run "separate_fast_registration" {
  command = plan

  variables {
    region                            = "US-EAST-04A"
    name                              = "union-prod"
    labels                            = { team = "platform" }
    separate_fast_registration_bucket = true
    fast_registration_retention_days  = 14
  }

  override_resource {
    target          = random_id.suffix
    override_during = plan
    values          = { hex = "a1b2c3" }
  }
  override_resource {
    target          = coreweave_cks_cluster.this
    override_during = plan
    values = {
      id                  = jsondecode(file("../helm/tests/fixtures/separate-fast-registration.json")).cluster_id
      api_server_endpoint = jsondecode(file("../helm/tests/fixtures/separate-fast-registration.json")).cluster_endpoint
    }
  }
  override_resource {
    target          = coreweave_object_storage_access_key.this
    override_during = plan
    values = {
      id         = jsondecode(file("../helm/tests/fixtures/separate-fast-registration.json")).access_key_id
      secret_key = jsondecode(file("../helm/tests/fixtures/separate-fast-registration.json")).secret_key
    }
  }

  assert {
    condition = jsonencode({
      access_key_id                 = output.access_key_id
      bucket_name                   = output.bucket_name
      cluster_endpoint              = output.cluster_endpoint
      cluster_id                    = output.cluster_id
      cluster_name                  = output.cluster_name
      fast_registration_bucket_name = output.fast_registration_bucket_name
      helm_values                   = output.helm_values
      object_storage_endpoint       = output.object_storage_endpoint
      region                        = output.region
      secret_key                    = nonsensitive(output.secret_key)
    }) == jsonencode(jsondecode(file("../helm/tests/fixtures/separate-fast-registration.json")))
    error_message = "The infra outputs for the separate-fast-registration scenario must equal ../helm/tests/fixtures/separate-fast-registration.json."
  }
}
