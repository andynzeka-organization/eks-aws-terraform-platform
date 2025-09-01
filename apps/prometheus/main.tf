module "prometheus" {
  source                      = "../../modules/prometheus"
  namespace                   = "monitoring"
  create_namespace            = true
  server_service_type         = "LoadBalancer"
  server_service_annotations  = {
    "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
  }
}

