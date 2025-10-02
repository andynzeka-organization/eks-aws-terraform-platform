resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd"
    namespace = var.namespace
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/group.name"  = var.alb_group_name
      "alb.ingress.kubernetes.io/subnets"     = join(",", var.public_subnet_ids)
      "alb.ingress.kubernetes.io/healthcheck-path" = "/argocd/"
      "alb.ingress.kubernetes.io/success-codes"    = "200-399"
    }
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path      = "/argocd"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 443 }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = false
  timeouts { create = "12m" }

  depends_on = [
    helm_release.argocd,
    null_resource.wait_argocd_server_ready,
    null_resource.wait_alb_controller
  ]
}
