module "argocd" {
  source            = "../../modules/argocd"
  namespace         = "argocd"
  create_namespace  = true
  service_type      = "LoadBalancer"
  service_annotations = {
    "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
  }
}

