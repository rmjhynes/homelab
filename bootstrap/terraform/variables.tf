variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "/home/rmjhynes/.kube/config"
}

variable "target_revision" {
  description = "Git branch for ArgoCD to sync from"
  type        = string
  default     = "HEAD"
}
