#!/usr/bin/env bash
set -euo pipefail

# Destroys all ALB-related Kubernetes resources safely, then destroys Terraform stacks
# WARNING: This is destructive. It will:
#  - Delete ALL Ingress resources in the cluster
#  - Wait for all TargetGroupBindings to be removed (avoids orphan ALBs)
#  - Uninstall the AWS Load Balancer Controller Helm release
#  - Delete the IngressClass and RBAC manifests added by this repo
#  - Run `terraform destroy -auto-approve` in `ingress/` and in repo root
#
# Env vars:
#  - RELEASE_NAME (default: aws-load-balancer-controller)
#  - RELEASE_NAMESPACE (default: kube-system)
#  - TIMEOUT (seconds, default: 1200)
#  - SLEEP (seconds between checks, default: 10)
#  - FORCE (true|false, default: false)  # set true to skip interactive confirmation

RELEASE_NAME=${RELEASE_NAME:-aws-load-balancer-controller}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-kube-system}
TIMEOUT=${TIMEOUT:-1200}
SLEEP=${SLEEP:-10}
FORCE=${FORCE:-false}
# Extra args for kubectl to avoid long hangs
KUBECTL_ARGS=(--request-timeout=10s)

confirm() {
  if [[ "${FORCE}" == "true" ]]; then
    return 0
  fi
  echo "This will delete ALL Ingresses, uninstall the controller, and destroy Terraform stacks." >&2
  read -r -p "Type 'yes' to proceed: " ans
  if [[ "${ans}" != "yes" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

tf_cmd() {
  if command -v terraform >/dev/null 2>&1; then
    terraform "$@"
  elif command -v tf >/dev/null 2>&1; then
    tf "$@"
  else
    echo "ERROR: terraform (or tf) binary not found in PATH" >&2
    exit 1
  fi
}

crd_exists() {
  kubectl "${KUBECTL_ARGS[@]}" get crd targetgroupbindings.elbv2.k8s.aws >/dev/null 2>&1
}

current_tgb_count() {
  if crd_exists; then
    kubectl "${KUBECTL_ARGS[@]}" get targetgroupbindings.elbv2.k8s.aws -A --no-headers 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

wait_for_tgbs() {
  local start_ts
  start_ts=$(date +%s)
  echo "[destroy] Waiting for TargetGroupBindings to clear..."
  while true; do
    local count
    count=$(current_tgb_count)
    echo "[destroy] TGB remaining: ${count}"
    if [[ "${count}" -eq 0 ]]; then
      echo "[destroy] All TargetGroupBindings removed."
      break
    fi
    local now
    now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[destroy] Timeout waiting for TGB cleanup (${count} remaining). Proceeding anyway." >&2
      break
    fi
    sleep "${SLEEP}"
  done
}

# Resolve VPC ID from env or terraform output
resolve_vpc_id() {
  if [[ -n "${VPC_ID:-}" ]]; then
    echo "${VPC_ID}"
    return 0
  fi
  # Try terraform output in repo root
  local v
  if v=$(terraform output -raw vpc_id 2>/dev/null); then
    echo "${v}"
    return 0
  fi
  if v=$(tf_cmd output -raw vpc_id 2>/dev/null); then
    echo "${v}"
    return 0
  fi
  echo "" # unresolved
}

wait_for_elbv2_cleanup() {
  local vpc_id="$1"
  local start_ts
  start_ts=$(date +%s)
  echo "[destroy] Waiting for ELBv2 resources in VPC ${vpc_id} to be deleted..."
  while true; do
    # Count ALBs in VPC
    local lb_count tg_count
    lb_count=$(aws elbv2 describe-load-balancers \
      --query "length(LoadBalancers[?VpcId=='${vpc_id}'])" 2>/dev/null || echo 0)
    # Count Target Groups in VPC
    tg_count=$(aws elbv2 describe-target-groups \
      --query "length(TargetGroups[?VpcId=='${vpc_id}'])" 2>/dev/null || echo 0)

    echo "[destroy] ALBs in VPC: ${lb_count} | TargetGroups in VPC: ${tg_count}"
    if [[ "${lb_count}" -eq 0 && "${tg_count}" -eq 0 ]]; then
      echo "[destroy] ELBv2 resources cleared."
      break
    fi
    local now
    now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[destroy] Timeout waiting for ELBv2 cleanup (ALBs=${lb_count}, TGs=${tg_count}). Proceeding anyway." >&2
      break
    fi
    sleep "${SLEEP}"
  done
}

main() {
  confirm

  # Ensure we run from repo root (script resides in scripts/)
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
  cd "${REPO_ROOT}"

  echo "[destroy] Deleting all Ingress resources cluster-wide..."
  # Delete all ingresses without waiting to avoid blocking on finalizers
  kubectl "${KUBECTL_ARGS[@]}" delete ingress --all --all-namespaces --wait=false 2>/dev/null || true

  wait_for_tgbs

  # Wait for AWS ELBv2 resources (ALBs/Target Groups) to disappear from the VPC
  VPC_ID_RESOLVED=$(resolve_vpc_id || true)
  if [[ -n "${VPC_ID_RESOLVED}" ]]; then
    wait_for_elbv2_cleanup "${VPC_ID_RESOLVED}"
  else
    echo "[destroy] Skipping ELBv2 wait: could not resolve VPC ID (set VPC_ID env to force)." >&2
  fi

  echo "[destroy] Uninstalling Helm release ${RELEASE_NAME} in ${RELEASE_NAMESPACE}..."
  helm uninstall "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" || true

  # Delete IngressClass + RBAC manifests if present
  if [[ -f "k8s-examples/aws-lb-controller-rbac/ingressclass-rbac.yaml" ]]; then
    echo "[destroy] Deleting IngressClass + RBAC manifests..."
    kubectl delete -f k8s-examples/aws-lb-controller-rbac/ingressclass-rbac.yaml --ignore-not-found || true
  fi
  if [[ -f "k8s-examples/aws-lb-controller-rbac/ingressclass-params.yaml" ]]; then
    kubectl delete -f k8s-examples/aws-lb-controller-rbac/ingressclass-params.yaml --ignore-not-found || true
  fi

  # Terraform destroy in ingress module
  if [[ -d "ingress" ]]; then
    echo "[destroy] Terraform destroy in ingress/ ..."
    (cd ingress && tf_cmd destroy -auto-approve) || true
  fi

  # Terraform destroy in repo root
  echo "[destroy] Terraform destroy in repo root ..."
  tf_cmd destroy -auto-approve || true

  echo "[destroy] Complete."
}

main "$@"
