
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "monitoring"
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/group.name"  = "monitoring"
      "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/grafana"
          path_type = "Prefix"
          backend {
            service {
              name = "grafana"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  # lifecycle {
  #   ignore_changes = [
  #     metadata[0].annotations["alb.ingress.kubernetes.io/target-group-attributes"],
  #     metadata[0].annotations["alb.ingress.kubernetes.io/subnets"]
  #   ]
  # }

  depends_on = [
    module.grafana
  ]
}

resource "null_resource" "remove_grafana_ingress_finalizers" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "kubectl patch ingress grafana -n monitoring -p '{\"metadata\":{\"finalizers\":null}}' --type=merge || true"
  }

  depends_on = [kubernetes_ingress_v1.grafana]
}
##########################

# resource "kubernetes_ingress_v1" "grafana" {
#   depends_on = [
#     helm_release.argocd,
#     kubernetes_service.argo_cd_server,
#     kubernetes_namespace.argocd
#     ]
#   metadata {
#     name      = "grafana"
#     namespace = "monitoring"
#     annotations = {
#       "kubernetes.io/ingress.class"           = "alb"
#       "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
#       "alb.ingress.kubernetes.io/target-type" = "ip"
#       "alb.ingress.kubernetes.io/group.name"  = "monitoring"
#       # Explicitly set public subnets to guarantee ALB provisioning
#       "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
#     }
#   }

#   spec {
#     ingress_class_name = "alb"

#     rule {
#       http {
#         path {
#           path      = "/grafana"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = "grafana"
#               port { number = 80 }
#             }
#           }
#         }
#       }
#     }
#   }

# }

