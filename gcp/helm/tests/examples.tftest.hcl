# checks.sh runs this once per examples/gcp/helm/*.tfvars, with its values as each run's variables. Each run plans the
# example against the infra outputs of one scenario.

mock_provider "helm" {}
mock_provider "kubernetes" {}

run "plans_against_basic" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
    }
  }
}

run "plans_against_gpu" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
    }
  }
}
