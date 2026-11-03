# Planned once per examples/coreweave/infra/*.tfvars by checks.sh (its values as each run's variables); no variables of
# its own.
mock_provider "coreweave" {}
mock_provider "random" {}

run "plan" {
  command = plan
}
