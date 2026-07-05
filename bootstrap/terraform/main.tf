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
  # Must match the version in applications/argocd/application.yaml, otherwise
  # the self-managed ArgoCD immediately replaces the bootstrapped install
  version    = "7.7.16"

  depends_on = [kubernetes_namespace.argocd]
}

resource "kubernetes_manifest" "argocd_project" {
  manifest = yamldecode(file("${path.module}/../project.yaml"))

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_applications" {
  # selfHeal is disabled when testing a branch; see the comment on selfHeal in
  # the template
  manifest = yamldecode(templatefile("${path.module}/../applications.yaml.tftpl", {
    target_revision = var.target_revision
    self_heal       = var.target_revision == "HEAD"
  }))

  depends_on = [helm_release.argocd]
}
