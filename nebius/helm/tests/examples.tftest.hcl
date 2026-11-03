# Planned once per examples/nebius/helm/*.tfvars by checks.sh (its values as each run's variables); no variables of its
# own. Each run plans the example against one fixture of the infra root's outputs.
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "basic" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/basic.json")) : k => v if v != null }
    }
  }
}

run "gpu" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/gpu.json")) : k => v if v != null }
    }
  }
}
