# Plans the root against each examples/azure/helm/*.tfvars (checks.sh makes its values each run's variables), once
# against each infra scenario's fixture: a helm example has to plan whichever infra example it follows. Null values are
# dropped from the fixtures, as state drops null root outputs.

mock_provider "helm" {}
mock_provider "kubernetes" {}

run "plans_after_infra_basic" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
    }
  }
}

run "plans_after_infra_gpu" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
    }
  }
}
