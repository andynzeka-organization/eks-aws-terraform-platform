resource "kubernetes_namespace" "argocd" {
  metadata { name = var.namespace }
}

resource "helm_release" "argocd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = var.namespace

  wait              = true
  timeout           = 600
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
    crds = { install = true }
    server = {
      service = {
        type = "ClusterIP"
      }
      ingress = { enabled = false }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}

