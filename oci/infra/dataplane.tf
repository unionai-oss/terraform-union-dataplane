# The Union dataplane layer on top of the base in main.tf.
# Docs: oci.md "Object storage", "Container Registry", "Data retention", "Identity & access".

# --- Storage and registry

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "metadata" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${local.unique_name}-metadata"
  access_type    = "NoPublicAccess"
  versioning     = "Enabled" # general doc: versioning recommended on the metadata bucket
  freeform_tags  = local.labels
}

resource "oci_objectstorage_bucket" "fast_registration" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "${local.unique_name}-fast-reg"
  access_type    = "NoPublicAccess"
  freeform_tags  = local.labels
}

resource "oci_objectstorage_object_lifecycle_policy" "fast_registration" {
  namespace = data.oci_objectstorage_namespace.this.namespace
  bucket    = oci_objectstorage_bucket.fast_registration.name

  rules {
    name        = "expire-fast-registration-code"
    action      = "DELETE"
    is_enabled  = true
    target      = "objects"
    time_amount = var.fast_registration_retention_days
    time_unit   = "DAYS"
  }

  # Object Storage only runs lifecycle deletes once the service is granted access (the policy below); the
  # policy is not referenced by this resource, so Terraform needs the explicit ordering.
  depends_on = [oci_identity_policy.object_storage_lifecycle]
}

resource "oci_artifacts_container_repository" "imagebuilder" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.unique_name}/imagebuilder"
  is_public      = false
  freeform_tags  = local.labels
}

# --- Identity: Option A (instance principals) always, as the docs recommend; Option B (S3-compatibility customer
# secret key) only when static_credentials_user_ocid is set. The chart's storage client can only use Option B (see
# the helm values below).

resource "oci_identity_dynamic_group" "nodes" {
  compartment_id = var.tenancy_ocid # dynamic groups live in the tenancy root
  name           = "${local.unique_name}-nodes"
  description    = "OKE worker nodes for Union data plane"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
  freeform_tags  = local.labels
}

resource "oci_identity_policy" "dataplane" {
  compartment_id = var.compartment_ocid
  name           = "${local.unique_name}-policy"
  description    = "Allow Union data plane access to Object Storage and OCIR"
  freeform_tags  = local.labels
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.metadata.name}'",
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='${oci_objectstorage_bucket.fast_registration.name}'",
    # The docs grant manage repos on the whole compartment. One repository is enough: Image Builder pushes every
    # image into imageBuilder.defaultRepository as a tag (its docs scope the AWS grant to that one ECR repository,
    # with no CreateRepository), so it never creates sibling repositories.
    "Allow dynamic-group ${oci_identity_dynamic_group.nodes.name} to manage repos in compartment id ${var.compartment_ocid} where target.repo.name = '${oci_artifacts_container_repository.imagebuilder.display_name}'",
  ]
}

# Required by OCI for any Object Storage lifecycle rule to execute (the docs' data-retention guidance relies on
# lifecycle rules; this grant is OCI's prerequisite for them).
resource "oci_identity_policy" "object_storage_lifecycle" {
  compartment_id = var.compartment_ocid
  name           = "${local.unique_name}-lifecycle"
  description    = "Allow Object Storage to run lifecycle rules"
  freeform_tags  = local.labels
  statements     = ["Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid}"]
}

resource "oci_identity_customer_secret_key" "s3" {
  # Option B is opt-in: the secret lands in Terraform state, so it is only created when a user is named.
  count = var.static_credentials_user_ocid == null ? 0 : 1

  user_id      = var.static_credentials_user_ocid
  display_name = "${local.unique_name}-s3-compat"
}

# --- Helm values: the documented OCI keys for the base dataplane values.yaml, plus the chart keys those need to
# work. The helm root layers the org, control plane host and client ID over them; the storage key is in the
# storage-credentials Secret, never in the values.

locals {
  image_builder_repository = "${var.region}.ocir.io/${data.oci_objectstorage_namespace.this.namespace}/${oci_artifacts_container_repository.imagebuilder.display_name}"

  # The chart (dataplane 2026.10.1, templates/_storage.tpl) has no instance-principal mode for Object Storage: its
  # "oci" provider renders an S3-compatibility client with auth_type accesskey whatever storage.authType says, and
  # with no endpoint that client talks to AWS. So storage always needs the S3-compatibility endpoint and a customer
  # secret key (Option B); the README says what to set without static_credentials_user_ocid.
  object_storage_endpoint = "https://${data.oci_objectstorage_namespace.this.namespace}.compat.objectstorage.${var.region}.oraclecloud.com"

  helm_values = yamlencode({
    global = {
      CLUSTER_NAME = oci_containerengine_cluster.this.name
    }
    storage = {
      provider                   = "oci"
      authType                   = "accesskey" # also what makes the chart pass the key to task pods
      endpoint                   = local.object_storage_endpoint
      bucketName                 = oci_objectstorage_bucket.metadata.name
      fastRegistrationBucketName = oci_objectstorage_bucket.fast_registration.name
      region                     = var.region
      # The chart reads the key from this Secret when it renders. The helm root creates it from the Option B key;
      # without one the operator creates it (README, Apply step 2).
      credentialsSecretRef = { name = "storage-credentials" }
    }
    # Without it the chart falls back to the bare registryName for any provider other than aws, gcp and azure.
    imageBuilder = {
      defaultRepository = local.image_builder_repository
    }
  })
}
