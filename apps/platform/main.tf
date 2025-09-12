module "argocd" {
  source           = "../../modules/argocd"
  namespace        = "argocd"
  create_namespace = true
  service_type     = "ClusterIP"
  service_annotations = {}
}

module "grafana" {
  source              = "../../modules/grafana"
  namespace           = "monitoring"
  create_namespace    = true
  service_type        = "ClusterIP"
  service_annotations = {}
  # depends_on          = [null_resource.alb_webhook_ready]
}
