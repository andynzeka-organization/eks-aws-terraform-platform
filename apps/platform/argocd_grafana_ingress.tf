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



# Strip Ingress finalizers right before destroy so Terraform doesn't hang
# waiting for the ALB controller to reconcile deletions.
resource "null_resource" "strip_ingress_finalizers_on_destroy" {
  depends_on = [
    kubernetes_ingress_v1.argocd,
    kubernetes_ingress_v1.grafana
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
echo "[destroy-pre] Stripping Ingress finalizers to prevent hang..."
kubectl patch ingress argocd -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge || true
kubectl patch ingress grafana -n monitoring -p '{"metadata":{"finalizers":[]}}' --type=merge || true
EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

