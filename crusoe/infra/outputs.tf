output "bucket_name" {
  description = "Cloud Storage bucket for metadata and fast registration (bucketName and fastRegistrationBucketName)."
  value       = crusoe_storage_s3_bucket.metadata.name
}

output "cluster_endpoint" {
  description = "DNS name of the CMK cluster API endpoint."
  value       = crusoe_kubernetes_cluster.this.dns_name
}

output "cluster_id" {
  description = "CMK cluster ID."
  value       = crusoe_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "CMK cluster name, to register with `flyte create cluster`. The helm root sets it as clusterName."
  value       = crusoe_kubernetes_cluster.this.name
}

output "helm_values" {
  description = "The Crusoe layer of the dataplane Helm values (YAML) per the Crusoe deploy page, without credentials or the org, host and client ID; the helm root adds those."
  value       = yamlencode(local.helm_values)
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for the cluster (Crusoe CLI); point KUBE_CONFIG_PATH at that kubeconfig for the helm root."
  value       = "crusoe kubernetes clusters get-credentials ${crusoe_kubernetes_cluster.this.name}"
}

output "location" {
  description = "Crusoe location (a zone, for example us-east1-a) of all resources: the value of var.region."
  value       = var.region
}

output "region" {
  description = "Crusoe region derived from the location (the location without its zone letter); value for storage.region and AWS_DEFAULT_REGION."
  value       = local.storage_region
}

output "storage_access_key_id" {
  description = "Access key ID for the storage-credentials Kubernetes secret (access_key_id); the helm root creates that Secret."
  value       = crusoe_storage_s3_key.this.access_key_id
}

output "storage_endpoint" {
  description = "Endpoint URL Crusoe reports for the bucket; value for storage.endpoint. Verify it is the S3 service endpoint (not bucket-specific) before installing."
  value       = crusoe_storage_s3_bucket.metadata.s3_url
}

output "storage_secret_access_key" {
  description = "Secret access key for the storage-credentials Kubernetes secret (secret_key); the helm root creates that Secret."
  value       = crusoe_storage_s3_key.this.secret_access_key
  sensitive   = true
}
