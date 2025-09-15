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
    null_resource.wait_alb_controller,
    null_resource.alb_webhook_ready
  ]

  wait_for_load_balancer = false
  timeouts {
    create = "10m"
  }
}


/*
##############################
# Grafana Ingress (disabled)
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
      # Health checks: target a concrete Grafana health endpoint under the subpath
      # and allow 2xx/3xx responses as success.
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/grafana/api/health"
      "alb.ingress.kubernetes.io/healthcheck-port"   = "traffic-port"
      "alb.ingress.kubernetes.io/success-codes"      = "200-399"
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
    null_resource.wait_alb_controller,
    null_resource.alb_webhook_ready,
    null_resource.wait_grafana_endpoints
  ]

  wait_for_load_balancer = false
  timeouts {
    create = "15m"
  }
}
*/

/* Ensure Grafana Service has ready endpoints before Ingress (disabled)
resource "null_resource" "wait_grafana_endpoints" {}
*/



# Strip Ingress finalizers right before destroy so Terraform doesn't hang
# waiting for the ALB controller to reconcile deletions.
##############################
# Strip finalizers before destroy
##############################
resource "null_resource" "strip_ingress_finalizers_on_destroy" {
  depends_on = [
    kubernetes_ingress_v1.argocd
  ]

  provisioner "local-exec" {
    command = <<EOT
echo "[destroy-pre] Stripping Ingress finalizers to prevent hang..."
kubectl patch ingress argocd -n argocd -p '{"metadata":{"finalizers":[]}}' --type=merge || true
# Grafana disabled
# kubectl patch ingress grafana -n monitoring -p '{"metadata":{"finalizers":[]}}' --type=merge || true
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

/*
resource "null_resource" "remove_grafana_ingress_finalizers" {
  # disabled
}
*/
##########################
resource "null_resource" "wait_alb_webhook" {
  provisioner "local-exec" {
    command = "kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=300s"
  }
  triggers = {
    always_run = timestamp()
  }
}
resource "null_resource" "wait_tgbs" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
echo "[wait] Waiting for Ingress hostnames (ALB ready)..."
START=$(date +%s)
TIMEOUT=$${TIMEOUT:-1200}
SLEEP=$${SLEEP:-10}

wait_ingress_hostname() {
  local ns="$1" name="$2"
  while true; do
    host=$(kubectl -n "$ns" get ingress "$name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    echo "  - $ns/$name hostname: $${host:-<none>}"
    if [[ -n "$${host:-}" ]]; then
      return 0
    fi
    now=$(date +%s)
    if (( now - START > TIMEOUT )); then
      echo "[wait] Timeout waiting for $ns/$name hostname; check controller logs and annotations." >&2
      return 1
    fi
    sleep "$$SLEEP"
  done
}

## Grafana disabled
wait_ingress_hostname argocd argocd
echo "[wait] Ingress hostnames are present."
EOT
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    kubernetes_ingress_v1.argocd
  ]
}
