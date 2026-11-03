# Planned once per examples/coreweave/helm/*.tfvars by checks.sh (its values as each run's variables); no variables of
# its own. Each example is planned against every infra scenario's outputs (tests/fixtures), one run each, with nulls
# dropped as remote state drops them (Terraform stores no root output whose value is null).
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "plan_minimal" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/minimal.json")) : k => v if v != null }
    }
  }
}

run "plan_separate_fast_registration" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/separate-fast-registration.json")) : k => v if v != null }
    }
  }
}
