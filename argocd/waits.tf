resource "null_resource" "wait_argocd_server_ready" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      NS="${var.namespace}"
      TIMEOUT=$${TIMEOUT:-300}
      echo "[wait] Waiting (up to $${TIMEOUT}s) for ArgoCD server rollout..."

      if ! kubectl -n "$${NS}" get deploy argocd-server >/dev/null 2>&1; then
        echo "[wait] Deployment argocd-server not found; skipping availability check (inspect helm_release.argocd if this persists)."
        exit 0
      fi

      desired=$(kubectl -n "$${NS}" get deploy argocd-server -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
      if [[ -z "$${desired}" || "$${desired}" == "0" ]]; then
        echo "[wait] Deployment has 0 desired replicas; skipping availability wait."
        exit 0
      fi

      if ! kubectl -n "$${NS}" rollout status deploy/argocd-server --timeout=$${TIMEOUT}s; then
        echo "[wait] Timeout waiting for ArgoCD server deployment." >&2
        kubectl -n "$${NS}" get deploy argocd-server -o wide || true
        kubectl -n "$${NS}" get pods -l app.kubernetes.io/name=argocd-server || true
        exit 1
      fi

      echo "[wait] ArgoCD server rollout reported Available."
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

  triggers   = { always_run = timestamp() }
  depends_on = [kubernetes_ingress_v1.argocd]
}

resource "null_resource" "strip_ingress_finalizers_on_destroy" {
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail

disable_alb_webhooks_if_unavailable() {
  local wait_seconds=60
  echo "[destroy-pre] Checking ALB webhooks availability..."
  if kubectl -n kube-system get deploy aws-load-balancer-controller >/dev/null 2>&1; then
    echo "[destroy-pre] Waiting up to $${wait_seconds}s for aws-load-balancer-controller to be Available..."
    if ! kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=$${wait_seconds}s >/dev/null 2>&1; then
      echo "[destroy-pre] Controller not Available; removing webhook configurations."
      cleanup_webhooks
    else
      echo "[destroy-pre] ALB controller is Available; proceeding."
    fi
  else
    echo "[destroy-pre] ALB controller deployment not found; removing webhook configurations if present."
    cleanup_webhooks
  fi
}

cleanup_webhooks() {
  for kind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
    for w in $(kubectl get $${kind} -o name 2>/dev/null | grep -E 'elbv2\.k8s\.aws|aws-load-balancer' || true); do
      echo "    - deleting $${w}"
      kubectl delete "$${w}" --ignore-not-found >/dev/null 2>&1 || true
    done
  done
}

disable_alb_webhooks_if_unavailable || true

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
