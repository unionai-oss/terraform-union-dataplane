# The helm root's tests plan against tests/fixtures/*.json in ../helm, which stand in for this root's outputs. Each run
# here plans this root for one fixture's scenario, with the values unknown at plan taken from that fixture, and checks
# that every output known at plan is what the fixture says (CONVENTIONS.md section 8). cluster_ca_certificate is read
# from the cluster's kubeconfig only once the cluster exists, so it is checked by name only, by checks.sh.
mock_provider "oci" {}
mock_provider "random" {}

# The suffix both fixtures' names carry.
override_resource {
  target          = random_id.suffix
  override_during = plan
  values          = { hex = "a1b2c3" }
}

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

# The scenarios of the fixtures: the minimal example, with and without the Option B storage key.
variables {
  region           = "us-ashburn-1"
  tenancy_ocid     = "ocid1.tenancy.oc1..example"
  compartment_ocid = "ocid1.compartment.oc1..example"
  api_allowed_cidr = "203.0.113.0/24"
}

run "minimal" {
  command = plan

  override_data {
    target          = data.oci_objectstorage_namespace.this
    override_during = plan
    values          = { namespace = jsondecode(file("../helm/tests/fixtures/minimal.json")).object_storage_namespace }
  }

  override_resource {
    target          = oci_containerengine_cluster.this
    override_during = plan
    values = {
      id        = jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_id
      endpoints = [{ public_endpoint = trimprefix(jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_endpoint, "https://") }]
    }
  }

  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).bucket_name)
    error_message = "output bucket_name differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.cluster_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_id)
    error_message = "output cluster_id differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).cluster_name)
    error_message = "output cluster_name differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.dynamic_group_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).dynamic_group_name)
    error_message = "output dynamic_group_name differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.fast_registration_bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).fast_registration_bucket_name)
    error_message = "output fast_registration_bucket_name differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).helm_values)
    error_message = "output helm_values differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.image_builder_repository) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).image_builder_repository)
    error_message = "output image_builder_repository differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.object_storage_namespace) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).object_storage_namespace)
    error_message = "output object_storage_namespace differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).region)
    error_message = "output region differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(output.s3_access_key) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).s3_access_key)
    error_message = "output s3_access_key differs from the helm fixture minimal.json."
  }
  assert {
    condition     = jsonencode(nonsensitive(output.s3_secret_key)) == jsonencode(jsondecode(file("../helm/tests/fixtures/minimal.json")).s3_secret_key)
    error_message = "output s3_secret_key differs from the helm fixture minimal.json."
  }
}

run "static-credentials" {
  command = plan

  variables {
    static_credentials_user_ocid = "ocid1.user.oc1..example"
  }

  override_data {
    target          = data.oci_objectstorage_namespace.this
    override_during = plan
    values          = { namespace = jsondecode(file("../helm/tests/fixtures/static-credentials.json")).object_storage_namespace }
  }

  override_resource {
    target          = oci_containerengine_cluster.this
    override_during = plan
    values = {
      id        = jsondecode(file("../helm/tests/fixtures/static-credentials.json")).cluster_id
      endpoints = [{ public_endpoint = trimprefix(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).cluster_endpoint, "https://") }]
    }
  }

  override_resource {
    target          = oci_identity_customer_secret_key.s3[0]
    override_during = plan
    values = {
      id  = jsondecode(file("../helm/tests/fixtures/static-credentials.json")).s3_access_key
      key = jsondecode(file("../helm/tests/fixtures/static-credentials.json")).s3_secret_key
    }
  }

  assert {
    condition     = jsonencode(output.bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).bucket_name)
    error_message = "output bucket_name differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.cluster_endpoint) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).cluster_endpoint)
    error_message = "output cluster_endpoint differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.cluster_id) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).cluster_id)
    error_message = "output cluster_id differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.cluster_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).cluster_name)
    error_message = "output cluster_name differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.dynamic_group_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).dynamic_group_name)
    error_message = "output dynamic_group_name differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.fast_registration_bucket_name) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).fast_registration_bucket_name)
    error_message = "output fast_registration_bucket_name differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.helm_values) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).helm_values)
    error_message = "output helm_values differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.image_builder_repository) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).image_builder_repository)
    error_message = "output image_builder_repository differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.kubeconfig_command) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).kubeconfig_command)
    error_message = "output kubeconfig_command differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.object_storage_namespace) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).object_storage_namespace)
    error_message = "output object_storage_namespace differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.region) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).region)
    error_message = "output region differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(output.s3_access_key) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).s3_access_key)
    error_message = "output s3_access_key differs from the helm fixture static-credentials.json."
  }
  assert {
    condition     = jsonencode(nonsensitive(output.s3_secret_key)) == jsonencode(jsondecode(file("../helm/tests/fixtures/static-credentials.json")).s3_secret_key)
    error_message = "output s3_secret_key differs from the helm fixture static-credentials.json."
  }
}
