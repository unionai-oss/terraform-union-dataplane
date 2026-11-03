# Credential-free mock plans: configuration behaviour only, nothing is provisioned.
mock_provider "oci" {
  mock_data "oci_objectstorage_namespace" {
    defaults = {
      namespace = "exampletenancy"
    }
  }
}
mock_provider "random" {}

override_resource {
  target          = random_id.suffix
  override_during = plan
  values = {
    hex = "a1b2c3"
  }
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

override_resource {
  target          = oci_containerengine_cluster.this
  override_during = plan
  values = {
    id        = "cluster-id"
    endpoints = [{ public_endpoint = "203.0.113.10:6443" }]
  }
}

variables {
  region           = "us-ashburn-1"
  tenancy_ocid     = "tenancy-id"
  compartment_ocid = "compartment-id"
  api_allowed_cidr = "203.0.113.0/24"
  name             = "demo"
}

run "defaults" {
  command = plan

  assert {
    condition     = oci_objectstorage_bucket.metadata.versioning == "Enabled" && oci_objectstorage_bucket.metadata.access_type == "NoPublicAccess" && oci_objectstorage_bucket.fast_registration.access_type == "NoPublicAccess"
    error_message = "Buckets must be private and the metadata bucket versioned."
  }

  assert {
    condition     = one(oci_objectstorage_object_lifecycle_policy.fast_registration.rules).time_amount == "7"
    error_message = "Fast-registration objects must expire after 7 days by default."
  }

  assert {
    condition     = oci_objectstorage_object_lifecycle_policy.fast_registration.bucket == "demo-a1b2c3-fast-reg" && one(oci_objectstorage_object_lifecycle_policy.fast_registration.rules).action == "DELETE"
    error_message = "The DELETE lifecycle rule must target the fast-registration bucket, never the metadata bucket."
  }

  assert {
    condition     = oci_objectstorage_object_lifecycle_policy.fast_registration.bucket != oci_objectstorage_bucket.metadata.name
    error_message = "The DELETE lifecycle rule must not target the metadata bucket."
  }

  assert {
    condition     = oci_artifacts_container_repository.imagebuilder.display_name == "demo-a1b2c3/imagebuilder" && oci_artifacts_container_repository.imagebuilder.is_public == false
    error_message = "The image-builder repository must be private and named from var.name and the suffix."
  }

  assert {
    condition     = length(oci_identity_customer_secret_key.s3) == 0
    error_message = "No customer secret key expected without static_credentials_user_ocid."
  }

  assert {
    condition     = oci_identity_dynamic_group.nodes.compartment_id == "tenancy-id" && oci_identity_dynamic_group.nodes.name == "demo-a1b2c3-nodes"
    error_message = "The dynamic group must live in the tenancy and derive its name from var.name and the suffix."
  }

  # Each grant is pinned to one bucket or repository: an unscoped "manage objects" or "manage repos" would give
  # the nodes the whole compartment.
  assert {
    condition = tolist(oci_identity_policy.dataplane.statements) == tolist([
      "Allow dynamic-group demo-a1b2c3-nodes to manage objects in compartment id compartment-id where target.bucket.name='demo-a1b2c3-metadata'",
      "Allow dynamic-group demo-a1b2c3-nodes to manage objects in compartment id compartment-id where target.bucket.name='demo-a1b2c3-fast-reg'",
      "Allow dynamic-group demo-a1b2c3-nodes to manage repos in compartment id compartment-id where target.repo.name = 'demo-a1b2c3/imagebuilder'",
    ])
    error_message = "The policy must grant the dynamic group access to exactly the two buckets and the image-builder repository."
  }

  assert {
    condition     = oci_identity_dynamic_group.nodes.matching_rule == "ALL {instance.compartment.id = 'compartment-id'}"
    error_message = "The dynamic group must match only instances in the dataplane compartment."
  }

  assert {
    condition     = !contains(keys(yamldecode(output.helm_values).storage), "accessKey") && !contains(keys(yamldecode(output.helm_values).storage), "secretKey")
    error_message = "helm_values must not carry a storage key: the chart reads it from the storage-credentials Secret."
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.credentialsSecretRef == { name = "storage-credentials" }
    error_message = "helm_values must point the chart at the storage-credentials Secret."
  }
  assert {
    condition     = output.s3_access_key == null && output.s3_secret_key == null
    error_message = "No storage key outputs with instance principals."
  }

  # The chart's only Object Storage client is the S3-compatibility one: without these it would talk to AWS S3.
  assert {
    condition     = yamldecode(output.helm_values).storage.provider == "oci" && yamldecode(output.helm_values).storage.authType == "accesskey"
    error_message = "helm_values must select the chart's oci storage provider with access-key auth."
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.endpoint == "https://exampletenancy.compat.objectstorage.us-ashburn-1.oraclecloud.com"
    error_message = "storage.endpoint must be the tenancy's S3-compatibility endpoint in the region."
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == oci_objectstorage_bucket.metadata.name && yamldecode(output.helm_values).storage.fastRegistrationBucketName == oci_objectstorage_bucket.fast_registration.name
    error_message = "helm_values must name the metadata and fast-registration buckets."
  }
  assert {
    condition     = yamldecode(output.helm_values).imageBuilder.defaultRepository == output.image_builder_repository
    error_message = "imageBuilder.defaultRepository must be the OCIR repository the policy grants."
  }

  assert {
    condition     = yamldecode(output.helm_values).global == { CLUSTER_NAME = "demo" }
    error_message = "helm_values must carry the cluster name and nothing else in global: the org settings are the helm root's."
  }

  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == "demo-a1b2c3-metadata" && yamldecode(output.helm_values).storage.fastRegistrationBucketName == "demo-a1b2c3-fast-reg" && yamldecode(output.helm_values).storage.region == "us-ashburn-1"
    error_message = "helm_values must name both buckets and the region."
  }

  assert {
    condition     = output.image_builder_repository == "us-ashburn-1.ocir.io/exampletenancy/demo-a1b2c3/imagebuilder"
    error_message = "image_builder_repository must be region.ocir.io/<namespace>/<repository>."
  }

  # The kubeconfig, and so cluster_ca_certificate, is read only once the cluster exists, so its value is unknown at
  # plan and checked by name only (by checks.sh); this assert checks which kubeconfig it is.
  assert {
    condition     = data.oci_containerengine_cluster_kube_config.this.cluster_id == oci_containerengine_cluster.this.id && data.oci_containerengine_cluster_kube_config.this.endpoint == "PUBLIC_ENDPOINT"
    error_message = "the kubeconfig must be the cluster's, for its public endpoint."
  }
}

run "static_credentials_opt_in" {
  command = plan

  variables {
    static_credentials_user_ocid = "user-id"
  }

  assert {
    condition     = length(oci_identity_customer_secret_key.s3) == 1 && oci_identity_customer_secret_key.s3[0].user_id == "user-id"
    error_message = "A customer secret key must be created for the named user."
  }
}

# Compare helm_values with the resources themselves, not with the literals they were planned from, so a swapped
# reference is caught.
run "helm_values_match_resources" {
  command = plan

  variables {
    static_credentials_user_ocid = "user-id"
  }

  override_resource {
    target          = oci_identity_customer_secret_key.s3[0]
    override_during = plan
    values          = { id = "key-id", key = "key-example" }
  }

  assert {
    condition     = yamldecode(output.helm_values).global.CLUSTER_NAME == oci_containerengine_cluster.this.name
    error_message = "global.CLUSTER_NAME must be the cluster name."
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.bucketName == oci_objectstorage_bucket.metadata.name && yamldecode(output.helm_values).storage.fastRegistrationBucketName == oci_objectstorage_bucket.fast_registration.name
    error_message = "storage bucket names must be the metadata and fast-registration buckets, not swapped."
  }
  assert {
    condition     = yamldecode(output.helm_values).storage.region == var.region && yamldecode(output.helm_values).storage.provider == "oci"
    error_message = "storage.region must be the region, with the oci storage provider."
  }
  # The helm root puts these two in the storage-credentials Secret.
  assert {
    condition     = output.s3_access_key == oci_identity_customer_secret_key.s3[0].id && nonsensitive(output.s3_secret_key) == oci_identity_customer_secret_key.s3[0].key
    error_message = "with Option B the key outputs must be the Terraform-created customer secret key."
  }
  assert {
    condition     = !contains(keys(yamldecode(output.helm_values).storage), "accessKey")
    error_message = "with Option B too the key stays out of helm_values."
  }
}

