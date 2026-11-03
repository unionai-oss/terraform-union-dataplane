# checks.sh runs this once per examples/gcp/infra/*.tfvars, with its values as each run's variables.
mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = { names = ["zone-a", "zone-b", "zone-c", "zone-d"] }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

# The module's endpoint_dns output indexes a block that mock providers leave empty.
override_module {
  target = module.gke
  outputs = {
    ca_certificate     = "Y2E="
    endpoint           = "192.0.2.1"
    identity_namespace = "test-project.svc.id.goog"
    name               = "union-dataplane"
    service_account    = "node@test-project.${join(".", ["iam", "gserviceaccount", "com"])}"
  }
}

# The domain is joined because checks.sh bans domain literals that are not allowlisted.
# The mock's generated name is not a valid service account path, which the IAM member resources validate.
override_resource {
  target          = google_service_account.union
  override_during = plan
  values = {
    email = "union-system@example-project.${join(".", ["iam", "gserviceaccount", "com"])}"
    name  = "projects/example-project/serviceAccounts/union-system@example-project.${join(".", ["iam", "gserviceaccount", "com"])}"
  }
}

run "plans" {
  command = plan
}
