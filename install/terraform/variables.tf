variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "/etc/rancher/k3s/k3s.yaml"
}

variable "target_revision" {
  description = "Git branch for ArgoCD to sync from"
  type        = string
  default     = "HEAD"
}

