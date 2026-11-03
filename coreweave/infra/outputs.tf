output "access_key_id" {
  description = "Object storage access key ID (access_key_id field of the storage-credentials Secret the helm root creates)."
  value       = coreweave_object_storage_access_key.this.id
}

output "bucket_name" {
  description = "Metadata bucket name (storage.bucketName in the Helm values)."
  value       = coreweave_object_storage_bucket.metadata.name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint. The provider issues no kubeconfig: download it from the CoreWeave Cloud Console (Kubernetes > Clusters) and point KUBE_CONFIG_PATH at it for the helm root."
  value       = coreweave_cks_cluster.this.api_server_endpoint
}

output "cluster_id" {
  description = "CKS cluster ID."
  value       = coreweave_cks_cluster.this.id
}

output "cluster_name" {
  description = "CKS cluster name (use as <CLUSTER_NAME> for `flyte create cluster`; the helm root sets it as clusterName)."
  value       = coreweave_cks_cluster.this.name
}

output "fast_registration_bucket_name" {
  description = "Fast-registration bucket name (storage.fastRegistrationBucketName); equals bucket_name unless a separate bucket was requested."
  value       = local.fast_registration_bucket
}

output "helm_values" {
  description = "The CoreWeave layer of the dataplane Helm values (YAML) per the CoreWeave deploy page, without credentials or the org, host and client ID; the helm root adds those."
  value       = local.helm_values
}

output "object_storage_endpoint" {
  description = "S3 endpoint for AI Object Storage (the stow endpoint in the Helm values)."
  value       = "https://cwobject.com"
}

output "region" {
  description = "Availability Zone of the cluster and buckets; also the S3 region in the Helm values."
  value       = var.region
}

output "secret_key" {
  description = "Object storage secret key (secret_key field of the storage-credentials Secret the helm root creates)."
  value       = coreweave_object_storage_access_key.this.secret_key
  sensitive   = true
}
