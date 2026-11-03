output "account_id" {
  description = "AWS account ID (global.AWS_ACCOUNT_ID)."
  value       = data.aws_caller_identity.current.account_id
}

output "bucket_name" {
  description = "Metadata bucket name (global.METADATA_BUCKET)."
  value       = aws_s3_bucket.this["metadata"].bucket
}

output "cluster_ca_certificate" {
  description = "Base64-encoded certificate authority of the EKS cluster."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name (global.CLUSTER_NAME; register the same name with the Union control plane)."
  value       = module.eks.cluster_name
}

output "ecr_repository_name" {
  description = "ECR repository name (imageBuilder.registryName)."
  value       = aws_ecr_repository.image_builder.name
}

output "ecr_repository_url" {
  description = "ECR repository URI used for task images."
  value       = aws_ecr_repository.image_builder.repository_url
}

output "fast_registration_bucket" {
  description = "Fast-registration bucket name (global.FAST_REGISTRATION_BUCKET)."
  value       = aws_s3_bucket.this["fast_reg"].bucket
}

output "gpu_node_pool" {
  description = "The gpu_node_pool input, for the helm root (it installs the NVIDIA device plugin when the pool is enabled)."
  value       = var.gpu_node_pool
}

output "gpu_node_selector" {
  description = "Node labels that select the GPU pool's nodes, for the helm root (the NVIDIA device plugin's nodeSelector)."
  value       = local.gpu_node_selector
}

output "helm_values" {
  description = "YAML with the dataplane chart's global keys for this cluster (cluster, buckets, account, region, IRSA role) and its registry name. The helm root installs the chart with it; the org, control plane host and client ID are helm inputs."
  value = yamlencode({
    global = {
      CLUSTER_NAME             = module.eks.cluster_name
      AWS_ACCOUNT_ID           = data.aws_caller_identity.current.account_id
      AWS_REGION               = var.region
      METADATA_BUCKET          = aws_s3_bucket.this["metadata"].bucket
      FAST_REGISTRATION_BUCKET = aws_s3_bucket.this["fast_reg"].bucket
      BACKEND_IAM_ROLE_ARN     = aws_iam_role.union_system.arn
      WORKER_IAM_ROLE_ARN      = aws_iam_role.union_system.arn
    }
    imageBuilder = {
      registryName = aws_ecr_repository.image_builder.name
    }
  })
}

output "iam_role_arn" {
  description = "IRSA role ARN for backend and worker pods (global.BACKEND_IAM_ROLE_ARN / WORKER_IAM_ROLE_ARN)."
  value       = aws_iam_role.union_system.arn
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for the cluster."
  value       = module.eks.oidc_provider_arn
}

output "region" {
  description = "AWS region (global.AWS_REGION)."
  value       = var.region
}
