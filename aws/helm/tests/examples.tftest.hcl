# Plans this root against each examples/aws/helm/*.tfvars (checks.sh makes its values each run's variables), once for
# each infra example in tests/fixtures: a helm example has to plan whichever infra example it is applied after. No
# variables block: the values come from the example.

mock_provider "kubernetes" {}
mock_provider "helm" {}

# Null outputs are left out, as Terraform leaves them out of state.
run "after_minimal" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/minimal.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = helm_release.dataplane.chart == "dataplane"
    error_message = "the example installs the dataplane"
  }
}

run "after_gpu_and_spot" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu-and-spot.json")) : k => v if v != null }
    }
  }

  assert {
    condition     = helm_release.dataplane.chart == "dataplane"
    error_message = "the example installs the dataplane"
  }
}
