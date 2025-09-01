module "grafana" {
  source            = "../../modules/grafana"
  namespace         = "monitoring"
  create_namespace  = false
  service_type      = "ClusterIP"
  service_annotations = {}
}
