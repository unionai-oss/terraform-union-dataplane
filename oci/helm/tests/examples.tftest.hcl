# Planned once per examples/oci/helm/*.tfvars by checks.sh (its values as each run's variables); no variables of its
# own. Each run plans the example against one fixture of the infra root's outputs.
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "minimal" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/minimal.json")) : k => v if v != null }
    }
  }
}

run "static_credentials" {
  command = plan

  override_data {
    target = data.terraform_remote_state.infra
    values = {
      outputs = { for k, v in jsondecode(file("tests/fixtures/static-credentials.json")) : k => v if v != null }
    }
  }
}
