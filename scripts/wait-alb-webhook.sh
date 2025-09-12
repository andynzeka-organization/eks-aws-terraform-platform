#!/usr/bin/env bash
set -euo pipefail

# Wait until the AWS Load Balancer Controller webhook endpoints are ready.
# Exits 0 on success, non-zero on timeout.
# Env:
#   TIMEOUT (seconds, default 1800)
#   SLEEP   (seconds, default 10)

TIMEOUT=${TIMEOUT:-1800}
SLEEP=${SLEEP:-10}
KUBECTL_ARGS=(--request-timeout=10s)

echo "[wait-alb-webhook] Checking aws-load-balancer-webhook-service endpoints in kube-system..."
start_ts=$(date +%s)
while true; do
  if kubectl "${KUBECTL_ARGS[@]}" -n kube-system get svc aws-load-balancer-webhook-service >/dev/null 2>&1; then
    addrs=$(kubectl "${KUBECTL_ARGS[@]}" -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    ports=$(kubectl "${KUBECTL_ARGS[@]}" -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].ports[*].port}' 2>/dev/null || true)
    echo "  endpoints: IPs=[${addrs:-}] ports=[${ports:-}]"
    if [[ -n "${addrs:-}" && "${ports:-}" == *"9443"* ]]; then
      echo "[wait-alb-webhook] Webhook endpoints are ready."
      exit 0
    fi
  fi
  now=$(date +%s)
  if (( now - start_ts > TIMEOUT )); then
    echo "[wait-alb-webhook] Timed out waiting for ALB controller webhook endpoints (9443)." >&2
    exit 1
  fi
  sleep "${SLEEP}"
done
