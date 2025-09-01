resource "kubernetes_namespace" "prometheus_namespace" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = var.namespace
  wait       = true
  timeout    = 900

  values = [yamlencode({
    server = {
      service = {
        type        = var.server_service_type
        annotations = var.server_service_annotations
      }
      ingress = {
        enabled = false
      }
      persistentVolume = {
        enabled = var.server_persistence_enabled
      }
    }
    alertmanager = {
      service = {
        type = var.alertmanager_service_type
      }
      ingress = {
        enabled = false
      }
      persistentVolume = {
        enabled = var.alertmanager_persistence_enabled
      }
    }
    pushgateway = {
      service = {
        type = var.pushgateway_service_type
      }
    }
  })]

  depends_on = [kubernetes_namespace.prometheus_namespace]
}

data "kubernetes_service" "prometheus_server" {
  metadata {
    name      = "prometheus-server"
    namespace = var.namespace
  }
  depends_on = [helm_release.prometheus]
}
