resource "null_resource" "wait_argocd_server_ready" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
echo "[wait] Waiting for ArgoCD server deployment to be Available..."
START=$(date +%s)
TIMEOUT=$${TIMEOUT:-900}
SLEEP=$${SLEEP:-10}
while true; do
  avail=$(kubectl -n ${var.namespace} get deploy argo-cd-argocd-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
  repl=$(kubectl -n ${var.namespace} get deploy argo-cd-argocd-server -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
  echo "  - available/desired: $${avail:-0}/$${repl:-0}"
  [[ "$${avail:-0}" != "" ]] || avail=0
  [[ "$${repl:-0}" != "" ]] || repl=0
  if [[ $${repl:-0} -gt 0 && $${avail:-0} -eq $${repl:-0} ]]; then
    echo "[wait] ArgoCD server is Available."
    break
  fi
  now=$(date +%s)
  if (( now - START > TIMEOUT )); then
    echo "[wait] Timeout waiting for ArgoCD server deployment." >&2
    exit 1
  fi
  sleep "$SLEEP"
done
EOT
  }

  triggers = { always_run = timestamp() }

  depends_on = [helm_release.argocd]
}

resource "null_resource" "wait_alb_controller" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
if [[ "${var.wait_for_alb_controller}" != "true" ]]; then
  echo "[wait] Skipping ALB controller wait (disabled)."
  exit 0
fi
echo "[wait] Waiting for AWS Load Balancer Controller to be Available..."
kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=300s
EOT
  }

  triggers = { always_run = timestamp() }
}

resource "null_resource" "wait_ingress_hostname" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
echo "[wait] Waiting for Ingress hostname..."
START=$(date +%s)
TIMEOUT=$${TIMEOUT:-1200}
SLEEP=$${SLEEP:-10}
while true; do
  host=$(kubectl -n ${var.namespace} get ingress argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  echo "  - hostname: $${host:-<none>}"
  if [[ -n "$${host:-}" ]]; then
    break
  fi
  now=$(date +%s)
  if (( now - START > TIMEOUT )); then
    echo "[wait] Timeout waiting for Ingress hostname; check ALB controller." >&2
    exit 1
  fi
  sleep "$SLEEP"
done
EOT
  }

  triggers = { always_run = timestamp() }
  depends_on = [kubernetes_ingress_v1.argocd]
}

resource "null_resource" "strip_ingress_finalizers_on_destroy" {
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
echo "[destroy-pre] Stripping finalizers on Ingress argocd (all namespaces)..."
namespaces=$(kubectl get ingress -A -o jsonpath='{range .items[?(@.metadata.name=="argocd")]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null || true)
for ns in $namespaces; do
  echo "  - patching argocd in namespace: $ns"
  kubectl patch ingress argocd -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
done
EOT
  }
  triggers = { always_run = timestamp() }
}
