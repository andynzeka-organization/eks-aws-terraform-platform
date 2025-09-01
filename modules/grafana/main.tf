resource "kubernetes_namespace" "grafana_namespace" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = var.namespace
  wait       = true
  timeout    = 900

  values = [yamlencode({
    adminPassword = var.admin_password
    service = {
      type        = var.service_type
      annotations = var.service_annotations
    }
  })]

  depends_on = [kubernetes_namespace.grafana_namespace]
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = helm_release.grafana.name
    namespace = var.namespace
  }
  depends_on = [helm_release.grafana]
}

