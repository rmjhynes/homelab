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
  # When testing a branch (target_revision != HEAD), selfHeal is disabled so
  # that test_local.sh can patch child Applications to sync from the branch
  # without the root app reverting them
  manifest = yamldecode(
    replace(
      replace(
        file("${path.module}/../applications.yaml"),
        "targetRevision: HEAD",
        "targetRevision: ${var.target_revision}"
      ),
      "selfHeal: true",
      var.target_revision == "HEAD" ? "selfHeal: true" : "selfHeal: false"
    )
  )

  depends_on = [helm_release.argocd]
}
