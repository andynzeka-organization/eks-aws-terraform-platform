resource "kubernetes_namespace" "argocd_namespace" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6" # match with your values
  namespace  = var.namespace
  wait              = true
  timeout           = 300
  dependency_update = true
  atomic            = true
  cleanup_on_fail   = true

  values = [yamlencode({
    configs = {
      params = {
        "server.insecure" = true
        "server.basehref" = "/argocd"
        "server.rootpath" = "/argocd"
      }
    }
    crds = {
      install = true
    }
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
    kubernetes_namespace.argocd_namespace, 
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
