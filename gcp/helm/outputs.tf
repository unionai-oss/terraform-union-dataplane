output "chart_version" {
  description = "Version of the Union dataplane chart installed."
  value       = helm_release.dataplane.version
}

output "namespace" {
  description = "Namespace the dataplane release runs in, where the union-secret-auth Secret lives."
  value       = helm_release.dataplane.namespace
}
