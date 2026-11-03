output "namespace" {
  description = "Namespace of the Union dataplane release (kubectl -n)."
  value       = helm_release.dataplane.namespace
}
