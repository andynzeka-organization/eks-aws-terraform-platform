module "grafana" {
  source            = "../../modules/grafana"
  namespace         = "grafana"
  create_namespace  = true
  service_type      = "LoadBalancer"
  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
  }
}

