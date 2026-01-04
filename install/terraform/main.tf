resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "latest"

  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_manifest" "argocd_project" {
  manifest = yamldecode(file("${path.module}/../project.yaml"))

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_applications" {
  manifest = yamldecode(file("${path.module}/../applications.yaml"))

  depends_on = [helm_release.argocd]
}
