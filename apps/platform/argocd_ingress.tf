resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd"
    namespace = "argocd"
    
    annotations = merge({
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/group.name"  = "monitoring"
      "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
    }, {}) # ✅ This closing comma is required for valid `merge()` syntax
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
              name = "argo-cd-argocd-server"
              port {
                number = 443 # ✅ Make sure ArgoCD is actually listening on 443, not 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.argocd
  ]
}

# ###################################
# resource "kubernetes_ingress_v1" "argocd" {
#   metadata {
    
#     name      = "argocd"
#     namespace = "argocd"
#     annotations = {
#       "kubernetes.io/ingress.class"           = "alb"
#       "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
#       "alb.ingress.kubernetes.io/target-type" = "ip"
#       "alb.ingress.kubernetes.io/group.name"  = "monitoring"
#       "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
#     }
#   }
#   depends_on = [
#     module.argocd
#   ]
#   spec {
#     ingress_class_name = "alb"

#     rule {
#       http {
#         path {
#           path      = "/argocd"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = "argo-cd-argocd-server"
#               port { number = 80 }
#             }
#           }
#         }
#       }
#     }
#   }
  
# }

#############################


resource "null_resource" "remove_argocd_ingress_finalizers" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "kubectl patch ingress argocd -n argocd -p '{\"metadata\":{\"finalizers\":null}}' --type=merge || true"
  }

  depends_on = [kubernetes_ingress_v1.argocd]
}

##################

# resource "kubernetes_ingress_v1" "argocd" {
#   metadata {
#     name      = "argocd"
#     namespace = "argocd"
#     annotations = {
#       "kubernetes.io/ingress.class"           = "alb"
#       "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
#       "alb.ingress.kubernetes.io/target-type" = "ip"
#       "alb.ingress.kubernetes.io/group.name"  = "monitoring"
#       "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
#     }
#   }

#   spec {
#     ingress_class_name = "alb"

#     rule {
#       http {
#         path {
#           path      = "/argocd"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = "argo-cd-argocd-server"
#               port { number = 80 }
#             }
#           }
#         }
#       }
#     }
#   }



#   depends_on = [
#     helm_release.argocd,
#     kubernetes_service.argo_cd_server,
#     kubernetes_namespace.argocd
#   ]
# }
###################################
# resource "kubernetes_ingress_v1" "argocd" {
#   metadata {
#     name      = "argocd"
#     namespace = "argocd"
#     annotations = {
#       "kubernetes.io/ingress.class"           = "alb"
#       "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
#       "alb.ingress.kubernetes.io/target-type" = "ip"
#       # Share the same ALB as the monitoring ingress via group.name
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
#           path      = "/argocd"
#           path_type = "Prefix"
#           backend {
#             service {
#               name = "argo-cd-argocd-server"
#               port { number = 80 }
#             }
#           }
#         }
#       }
#     }
#   }
#     # 👇 Prevent destroy unless explicitly triggered
#   # lifecycle {
#   #   prevent_destroy = true
#   #   ignore_changes  = [metadata[0].annotations["alb.ingress.kubernetes.io/subnets"]]
#   # }
#   # Optional but useful for destroy reliability
#   lifecycle {
#     ignore_changes = [metadata[0].annotations["alb.ingress.kubernetes.io/target-group-attributes"]]
#   }
#   depends_on = [
#     helm_release.argocd,
#     kubernetes_service.argo_cd_server,
#     kubernetes_namespace.argocd
#   ]
# }

# resource "null_resource" "patch_ingress_finalizers" {
#   triggers = {
#     always_run = timestamp()
#   }

#   provisioner "local-exec" {
#     command = "kubectl patch ingress argocd -n argocd -p '{\"metadata\":{\"finalizers\":null}}' --type=merge || true"
#   }

#   depends_on = [kubernetes_ingress_v1.argocd]
# }
