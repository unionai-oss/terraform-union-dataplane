# Planned once per examples/oci/infra/*.tfvars by checks.sh (its values as each run's variables); no variables of its
# own.
mock_provider "oci" {}
mock_provider "random" {}

override_data {
  target          = data.oci_identity_availability_domains.this
  override_during = plan
  values = {
    availability_domains = [{ name = "ad-1" }]
  }
}

override_data {
  target          = data.oci_containerengine_node_pool_option.this
  override_during = plan
  values = {
    sources = [{ source_name = "Oracle-Linux-8-OKE-1.34.1-100", image_id = "image-x86" }]
  }
}

override_resource {
  target          = oci_containerengine_cluster.this
  override_during = plan
  values = {
    id        = "cluster-id"
    endpoints = [{ public_endpoint = "203.0.113.10:6443" }]
  }
}

run "plan" {
  command = plan
}
