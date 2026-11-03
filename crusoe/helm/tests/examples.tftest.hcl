# Planned once per examples/crusoe/helm/*.tfvars by checks.sh (its values as each run's variables); no variables of its
# own. Each example is planned against every infra scenario's outputs (tests/fixtures), one run each, with nulls dropped
# as remote state drops them (Terraform stores no root output whose value is null).
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "plan_basic" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
    }
  }
}

run "plan_gpu" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
    }
  }
}
