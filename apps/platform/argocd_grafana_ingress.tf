##############################
# ArgoCD Ingress
##############################
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
    }, {})
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
                number = 443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.argocd,
    null_resource.wait_alb_controller
  ]

  wait_for_load_balancer = true
}


##############################
# Grafana Ingress
##############################
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = "monitoring"

    annotations = merge({
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
      "alb.ingress.kubernetes.io/group.name"  = "monitoring"
      "alb.ingress.kubernetes.io/subnets"     = join(",", try(data.terraform_remote_state.infra.outputs.public_subnet_ids, []))
    }, {})
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
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    module.grafana,
    null_resource.wait_alb_controller
  ]

  wait_for_load_balancer = true
}



# Strip Ingress finalizers right before destroy so Terraform doesn't hang
# waiting for the ALB controller to reconcile deletions.
##############################
# Strip finalizers before destroy
##############################
resource "null_resource" "strip_ingress_finalizers_on_destroy" {
  depends_on = [
    kubernetes_ingress_v1.argocd,
    kubernetes_ingress_v1.grafana
  ]

  provisioner "local-exec" {
    command = <<EOT
echo "[destroy-pre] Stripping Ingress finalizers to prevent hang..."
kubectl patch ingress argocd -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge || true
kubectl patch ingress grafana -n monitoring -p '{"metadata":{"finalizers":[]}}' --type=merge || true
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}




##############################
# Wait for ALB Controller
##############################
resource "null_resource" "wait_alb_controller" {
  provisioner "local-exec" {
    command = <<EOT
kubectl -n kube-system wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller --timeout=300s
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}

# ##############################
# # Optional: Fix webhook SG permissions
# ##############################
# resource "null_resource" "validate_alb_webhook_sg" {
#   provisioner "local-exec" {
#     command = "chmod +x ./../../scripts/validate-alb-webhook-sg.sh && SG_VALIDATE_STRICT=false ./../../scripts/validate-alb-webhook-sg.sh || true"
#     interpreter = ["/bin/bash", "-c"]
#   }

#   triggers = {
#     always_run = timestamp()
#   }
# }

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
resource "null_resource" "wait_alb_webhook" {
  provisioner "local-exec" {
    command = "kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=300s"
  }
  triggers = {
    always_run = timestamp()
  }
}