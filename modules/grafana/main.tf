resource "kubernetes_namespace" "ns" {
  count = var.create_namespace ? 1 : 0
  metadata { name = var.namespace }
}

resource "random_password" "grafana_admin" {
  count   = var.admin_password == null ? 1 : 0
  length  = 20
  special = true
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "6.57.4" # or latest stable
  namespace  = var.namespace
  wait              = true
  timeout           = 300
  dependency_update = true
  atomic            = true
  cleanup_on_fail   = true

  values = [yamlencode({
    service = {
      type        = var.service_type
      annotations = var.service_annotations
    }
    # Configure Grafana to serve from the /grafana subpath
    "grafana.ini" = {
      server = {
        root_url            = "%(protocol)s://%(domain)s/grafana"
        serve_from_sub_path = true
      }
    }
    # No default data sources; keep Grafana independent of Prometheus
    adminPassword = coalesce(var.admin_password, try(random_password.grafana_admin[0].result, null))
  })]

  depends_on = [
    kubernetes_namespace.ns
  ]
}

data "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.namespace
  }
  depends_on = [helm_release.grafana]
}
