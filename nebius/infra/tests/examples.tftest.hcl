# checks.sh runs this once per examples/nebius/infra/*.tfvars, with its values as each run's variables.
mock_provider "nebius" {}
mock_provider "random" {}

run "plans" {
  command = plan
}
