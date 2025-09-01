resource "kubernetes_namespace" "argocd_namespace" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = var.namespace
  wait       = true
  timeout    = 600

  values = [yamlencode({
    server = {
      service = {
        type        = var.service_type
        annotations = var.service_annotations
      }
      ingress = {
        enabled = false
      }
    }
  })]

  depends_on = [
    kubernetes_namespace.argocd_namespace
  ]
}

data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argo-cd-argocd-server"
    namespace = var.namespace
  }
  depends_on = [helm_release.argocd]
}

data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.namespace
  }
  depends_on = [helm_release.argocd]
}
