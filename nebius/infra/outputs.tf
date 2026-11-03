output "access_key_id" {
  description = "Object Storage access key ID (AWS-style); the helm root puts it in the storage-credentials Secret as access_key_id."
  value       = nebius_iam_v2_access_key.this.status.aws_access_key_id
}

output "bucket_name" {
  description = "Metadata bucket name (storage.bucketName)."
  value       = nebius_storage_v1_bucket.metadata.name
}

output "cluster_ca_certificate" {
  description = "PEM CA certificate of the MK8s control plane."
  value       = nebius_mk8s_v1_cluster.this.status.control_plane.auth.cluster_ca_certificate
}

output "cluster_endpoint" {
  description = "Public endpoint of the MK8s control plane."
  value       = nebius_mk8s_v1_cluster.this.status.control_plane.endpoints.public_endpoint
}

output "cluster_id" {
  description = "MK8s cluster ID."
  value       = nebius_mk8s_v1_cluster.this.id
}

output "cluster_name" {
  description = "Cluster name; the value registered with `flyte create cluster` and set as clusterName in the Helm values."
  value       = nebius_mk8s_v1_cluster.this.name
}

output "fast_registration_bucket" {
  description = "Fast-registration bucket name (storage.fastRegistrationBucketName)."
  value       = nebius_storage_v1_bucket.fast_registration.name
}

output "helm_values" {
  description = "Nebius storage values for the dataplane chart (YAML), without credentials or org settings: the helm root adds those."
  value       = yamlencode(local.helm_values)
}

output "kubeconfig_command" {
  description = "Command that writes credentials for the cluster (Nebius CLI)."
  value       = "nebius mk8s cluster get-credentials --id ${nebius_mk8s_v1_cluster.this.id} --external"
}

output "region" {
  description = "Region of the cluster and buckets."
  value       = var.region
}

output "registry_id" {
  description = "Container registry ID."
  value       = nebius_registry_v1_registry.this.id
}

output "registry_url" {
  description = "Registry path for flyte.Image(registry=...), in the form shown on the deploy page (cr.<region>.nebius.cloud/<registry id without the registry- prefix>)."
  value       = "cr.${var.region}.nebius.cloud/${trimprefix(nebius_registry_v1_registry.this.id, "registry-")}"
}

output "secret_access_key" {
  description = "Object Storage secret key; the helm root puts it in the storage-credentials Secret as secret_key."
  value       = nebius_iam_v2_access_key.this.status.secret
  sensitive   = true
}

output "service_account_id" {
  description = "ID of the service account that owns the access key."
  value       = nebius_iam_v1_service_account.this.id
}

output "storage_endpoint" {
  description = "S3-compatible endpoint (storage.endpoint)."
  value       = local.storage_endpoint
}
