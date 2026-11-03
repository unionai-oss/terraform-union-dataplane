output "bucket_name" {
  description = "Metadata bucket name (storage.bucketName)."
  value       = oci_objectstorage_bucket.metadata.name
}

output "cluster_ca_certificate" {
  description = "PEM CA certificate of the OKE cluster, from the kubeconfig OKE generates."
  value       = base64decode(yamldecode(data.oci_containerengine_cluster_kube_config.this.content).clusters[0].cluster["certificate-authority-data"])
}

output "cluster_endpoint" {
  description = "Public Kubernetes API endpoint of the OKE cluster (https://host:port)."
  value       = "https://${oci_containerengine_cluster.this.endpoints[0].public_endpoint}"
}

output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.this.id
}

output "cluster_name" {
  description = "OKE cluster name; also use it for `flyte create cluster` and global.CLUSTER_NAME."
  value       = oci_containerengine_cluster.this.name
}

output "dynamic_group_name" {
  description = "Dynamic group granting instance-principal access to the buckets and registry."
  value       = oci_identity_dynamic_group.nodes.name
}

output "fast_registration_bucket_name" {
  description = "Fast-registration bucket name (storage.fastRegistrationBucketName)."
  value       = oci_objectstorage_bucket.fast_registration.name
}

output "helm_values" {
  description = "YAML of the OCI keys for the dataplane chart values, without credentials or org settings: the helm root adds those."
  value       = local.helm_values
}

output "image_builder_repository" {
  description = "OCIR repository path for the image builder (imageBuilder.defaultRepository)."
  value       = local.image_builder_repository
}

output "kubeconfig_command" {
  description = "OCI CLI command that writes a kubeconfig for the cluster."
  value       = "oci ce cluster create-kubeconfig --cluster-id ${oci_containerengine_cluster.this.id} --region ${var.region} --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT"
}

output "object_storage_namespace" {
  description = "Object Storage namespace (tenancy namespace)."
  value       = data.oci_objectstorage_namespace.this.namespace
}

output "region" {
  description = "OCI region (storage.region)."
  value       = var.region
}

output "s3_access_key" {
  description = "Option B only: S3-compatibility access key ID; the helm root puts it in the storage-credentials Secret. Null when using instance principals, and then absent from the state: Terraform stores no null root output."
  value       = one(oci_identity_customer_secret_key.s3[*].id)
}

output "s3_secret_key" {
  description = "Option B only: S3-compatibility secret key; the helm root puts it in the storage-credentials Secret. Null when using instance principals, and then absent from the state: Terraform stores no null root output."
  value       = one(oci_identity_customer_secret_key.s3[*].key)
  sensitive   = true
}
