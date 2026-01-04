output "argocd_namespace" {
  description = "The namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_release_status" {
  description = "Status of the ArgoCD Helm release"
  value       = helm_release.argocd.status
}

output "argocd_release_version" {
  description = "Version of the ArgoCD Helm chart deployed"
  value       = helm_release.argocd.version
}
