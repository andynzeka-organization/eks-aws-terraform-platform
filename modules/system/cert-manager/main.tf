resource "kubernetes_namespace" "this" {
  metadata { name = var.namespace }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.this.metadata[0].name
  wait       = true
  timeout    = 900
  values     = [yamlencode({ installCRDs = true })]

  depends_on = [kubernetes_namespace.this]
}

