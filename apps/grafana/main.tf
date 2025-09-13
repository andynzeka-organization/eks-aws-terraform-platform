module "grafana" {
  source            = "../../modules/grafana"
  namespace         = "monitoring"
  create_namespace  = true
  service_type      = "NodePort"
  service_annotations = {}
}
