# Create the ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }
}

# Install ArgoCD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_chart_version != "" ? var.argocd_chart_version : null

  depends_on = [kubernetes_namespace.argocd]
}

# Apply the AppProject manifest
resource "kubernetes_manifest" "argocd_project" {
  manifest = yamldecode(file("${path.module}/../project.yaml"))

  depends_on = [helm_release.argocd]
}

# Apply the root Application manifest
resource "kubernetes_manifest" "argocd_applications" {
  manifest = yamldecode(file("${path.module}/../applications.yaml"))

  depends_on = [helm_release.argocd]
}
