output "artifact_registry_path" {
  description = "Full Artifact Registry repository path."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository name (imageBuilder.registryName)."
  value       = google_artifact_registry_repository.this.repository_id
}

output "bucket_name" {
  description = "Metadata bucket name (global.METADATA_BUCKET)."
  value       = google_storage_bucket.metadata.name
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.gke.ca_certificate
  sensitive   = true
}

output "cluster_endpoint" {
  description = "GKE control plane endpoint: an IP address, without the https:// scheme."
  value       = module.gke.endpoint
  sensitive   = true
}

output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.name
}

output "fast_registration_bucket" {
  description = "Fast-registration bucket name (global.FAST_REGISTRATION_BUCKET)."
  value       = google_storage_bucket.fast_registration.name
}

output "helm_values" {
  description = "Infrastructure keys (global.*) for the Union dataplane chart, which the helm root passes to the release. CLUSTER_NAME is the GKE cluster name. The helm root adds the control plane host, org name and client ID."
  value = yamlencode({
    global = {
      CLUSTER_NAME             = module.gke.name
      GOOGLE_PROJECT_ID        = var.project_id
      GCP_REGION               = var.region
      METADATA_BUCKET          = google_storage_bucket.metadata.name
      FAST_REGISTRATION_BUCKET = google_storage_bucket.fast_registration.name
      BACKEND_IAM_ROLE_ARN     = google_service_account.union.email
      WORKER_IAM_ROLE_ARN      = google_service_account.union.email
    }
    imageBuilder = {
      registryName = google_artifact_registry_repository.this.repository_id
    }
  })
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for the cluster."
  value       = "gcloud container clusters get-credentials ${module.gke.name} --region ${var.region} --project ${var.project_id}"
}

output "namespace" {
  description = "Kubernetes namespace the Workload Identity bindings are for, and so the one the helm root installs the chart into."
  value       = var.namespace
}

output "node_service_account_email" {
  description = "Service account used by GKE nodes (Artifact Registry reader)."
  value       = module.gke.service_account
}

output "project_id" {
  description = "GCP project ID (global.GOOGLE_PROJECT_ID)."
  value       = var.project_id
}

output "region" {
  description = "GCP region (global.GCP_REGION)."
  value       = var.region
}

output "service_account_email" {
  description = "Google service account for union-system and union (global.BACKEND_IAM_ROLE_ARN and WORKER_IAM_ROLE_ARN)."
  value       = google_service_account.union.email
}
