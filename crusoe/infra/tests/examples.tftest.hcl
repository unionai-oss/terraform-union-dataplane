# checks.sh runs this once per examples/crusoe/infra/*.tfvars, with its values as each run's variables.
mock_provider "crusoe" {}
mock_provider "random" {}

override_resource {
  target          = crusoe_storage_s3_bucket.metadata
  override_during = plan
  values          = { s3_url = "https://storage.example.com" }
}

run "plans" {
  command = plan
}
