variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "/etc/rancher/k3s/k3s.yaml"
}

variable "argocd_chart_version" {
  description = "Version of the ArgoCD Helm chart (leave empty for latest)"
  type        = string
  default     = ""
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}
