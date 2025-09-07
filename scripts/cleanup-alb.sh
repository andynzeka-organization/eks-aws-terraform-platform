#!/usr/bin/env bash
set -euo pipefail

# Cleanup script for AWS Load Balancer Controller resources to avoid orphaned ALBs
#
# Behavior (configurable via env vars):
# - Optionally delete demo resources and/or all Ingresses
# - Waits until all TargetGroupBindings are gone (or timeout)
# - Uninstalls the controller Helm release
# - Optionally deletes the IngressClass + RBAC manifests we added
#
# Env vars:
# - RELEASE_NAME (default: aws-load-balancer-controller)
# - RELEASE_NAMESPACE (default: kube-system)
# - TIMEOUT (seconds, default: 1200)
# - SLEEP (seconds between checks, default: 10)
# - DELETE_DEMO (true|false, default: false)           # deletes k8s-examples/alb-echo
# - DELETE_ALL_INGRESSES (true|false, default: false)  # deletes all Ingress objects cluster-wide
# - DELETE_INGRESSCLASS (true|false, default: false)   # deletes IngressClass + RBAC manifests we added

RELEASE_NAME=${RELEASE_NAME:-aws-load-balancer-controller}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-kube-system}
TIMEOUT=${TIMEOUT:-1200}
SLEEP=${SLEEP:-10}
DELETE_DEMO=${DELETE_DEMO:-false}
DELETE_ALL_INGRESSES=${DELETE_ALL_INGRESSES:-false}
DELETE_INGRESSCLASS=${DELETE_INGRESSCLASS:-false}

echo "[cleanup] Using release ${RELEASE_NAME} in namespace ${RELEASE_NAMESPACE}"

if [[ "${DELETE_DEMO}" == "true" ]]; then
  if [[ -d "k8s-examples/alb-echo" ]]; then
    echo "[cleanup] Deleting demo app k8s-examples/alb-echo"
    kubectl delete -f k8s-examples/alb-echo/ --ignore-not-found || true
  else
    echo "[cleanup] Demo folder k8s-examples/alb-echo not found; skipping"
  fi
fi

if [[ "${DELETE_ALL_INGRESSES}" == "true" ]]; then
  echo "[cleanup] Deleting all Ingresses cluster-wide"
  # shellcheck disable=SC2046
  kubectl delete $(kubectl get ingress -A -o name) 2>/dev/null || true
fi

echo "[cleanup] Waiting for TargetGroupBindings to be removed"
start_ts=$(date +%s)

# If the CRD is missing, treat as zero to proceed
crd_exists() {
  kubectl get crd targetgroupbindings.elbv2.k8s.aws >/dev/null 2>&1
}

current_count() {
  if crd_exists; then
    kubectl get targetgroupbindings.elbv2.k8s.aws -A --no-headers 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

while true; do
  count=$(current_count)
  echo "[cleanup] TargetGroupBindings remaining: ${count}"
  if [[ "${count}" -eq 0 ]]; then
    echo "[cleanup] All TargetGroupBindings cleared"
    break
  fi
  now=$(date +%s)
  if (( now - start_ts > TIMEOUT )); then
    echo "[cleanup] Timeout reached with ${count} TargetGroupBindings still present."
    echo "           You may need to investigate in AWS (listeners/target groups) or retry later."
    break
  fi
  sleep "${SLEEP}"
done

echo "[cleanup] Uninstalling Helm release ${RELEASE_NAME}"
helm uninstall "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" || true

if [[ "${DELETE_INGRESSCLASS}" == "true" ]]; then
  if [[ -f "k8s-examples/aws-lb-controller-rbac/ingressclass-rbac.yaml" ]]; then
    echo "[cleanup] Deleting IngressClass + RBAC"
    kubectl delete -f k8s-examples/aws-lb-controller-rbac/ingressclass-rbac.yaml --ignore-not-found || true
  fi
  if [[ -f "k8s-examples/aws-lb-controller-rbac/ingressclass-params.yaml" ]]; then
    kubectl delete -f k8s-examples/aws-lb-controller-rbac/ingressclass-params.yaml --ignore-not-found || true
  fi
fi

echo "[cleanup] Done. You can now terraform destroy safely (ingress/ then root)."

