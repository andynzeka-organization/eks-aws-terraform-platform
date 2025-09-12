module "grafana" {
  source            = "../../modules/grafana"
  namespace         = "monitoring"
  create_namespace  = true
  service_type      = "ClusterIP"
  service_annotations = {}
}
