#!/usr/bin/env bash
set -euo pipefail

# End-to-end startup script to provision infra, install the ALB controller,
# and deploy platform apps (Argo CD, Grafana, Prometheus) behind a shared ALB.
#
# Order of operations
# 1) Root: terraform init && terraform apply -auto-approve
# 2) Wait for nodes Ready
# 3) Ingress/: terraform init -upgrade && terraform apply -auto-approve
# 4) Verify controller Deployment
# 5) argocd/: terraform init -upgrade && terraform apply -auto-approve
# 6) Print ArgoCD URL and verification tips
#
# Env vars:
# - AUTO_APPROVE=true|false (default true)
# - TIMEOUT (default 900 seconds) total wait for nodes/controller readiness
# - SLEEP   (default 10 seconds)  polling interval

AUTO_APPROVE=${AUTO_APPROVE:-true}
TIMEOUT=${TIMEOUT:-1800}
SLEEP=${SLEEP:-10}
KUBECTL_ARGS=(--request-timeout=10s)

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

apply_cmd() {
  if [[ "${AUTO_APPROVE}" == "true" ]]; then
    tf_cmd apply -auto-approve
  else
    tf_cmd apply
  fi
}

wait_for_nodes() {
  echo "[startup] Waiting for Kubernetes nodes to be Ready..."
  local start_ts; start_ts=$(date +%s)
  while true; do
    if kubectl "${KUBECTL_ARGS[@]}" get nodes >/dev/null 2>&1; then
      # Count Ready status
      ready=$(kubectl "${KUBECTL_ARGS[@]}" get nodes --no-headers 2>/dev/null | awk '$2 ~ /Ready/ {c++} END{print c+0}')
      total=$(kubectl "${KUBECTL_ARGS[@]}" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
      echo "  - nodes Ready: ${ready}/${total}"
      if [[ ${ready} -ge 1 && ${ready} -eq ${total} ]]; then
        echo "[startup] Nodes are Ready."
        break
      fi
    fi
    local now; now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[startup] Timed out waiting for nodes to be Ready." >&2
      exit 1
    fi
    sleep "${SLEEP}"
  done
}

wait_for_deploy() {
  local ns=$1 name=$2
  echo "[startup] Waiting for Deployment ${ns}/${name} to be Available..."
  local start_ts; start_ts=$(date +%s)
  while true; do
    if kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$name" >/dev/null 2>&1; then
      avail=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$name" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
      replicas=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$name" -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
      echo "  - available/desired: ${avail:-0}/${replicas:-0}"
      [[ "${avail:-0}" != "" ]] || avail=0
      [[ "${replicas:-0}" != "" ]] || replicas=0
      if [[ ${replicas:-0} -gt 0 && ${avail:-0} -eq ${replicas:-0} ]]; then
        echo "[startup] Deployment ${ns}/${name} is Available."
        break
      fi
    fi
    local now; now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[startup] Timed out waiting for deployment ${ns}/${name}." >&2
      exit 1
    fi
    sleep "${SLEEP}"
  done
}

wait_for_alb_webhook() {
  echo "[startup] Waiting for ALB controller webhook endpoints to be ready..."
  local start_ts; start_ts=$(date +%s)
  while true; do
    # Ensure Service exists
    if kubectl "${KUBECTL_ARGS[@]}" -n kube-system get svc aws-load-balancer-webhook-service >/dev/null 2>&1; then
      # Check endpoints have at least one address on port 9443
      addrs=$(kubectl "${KUBECTL_ARGS[@]}" -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
      ports=$(kubectl "${KUBECTL_ARGS[@]}" -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].ports[*].port}' 2>/dev/null || true)
      echo "  - webhook endpoints IPs: ${addrs:-<none>} ports: ${ports:-<none>}"
      if [[ -n "${addrs:-}" && "${ports:-}" == *"9443"* ]]; then
        echo "[startup] ALB controller webhook endpoints are ready."
        break
      fi
    fi
    local now; now=$(date +%s)
    if (( now - start_ts > TIMEOUT )); then
      echo "[startup] Timed out waiting for ALB webhook endpoints. Check SG rule clusterSG->nodeSG :9443 and controller logs." >&2
      exit 1
    fi
    sleep "${SLEEP}"
  done
}

ensure_prometheus_probes() {
  # Ensure Prometheus probes match the route prefix so the Service gets endpoints
  local ns=monitoring deploy=prometheus-server
  if ! kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$deploy" >/dev/null 2>&1; then
    return 0
  fi
  local lpath rpath
  lpath=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.template.spec.containers[?(@.name=="prometheus-server")].livenessProbe.httpGet.path}' 2>/dev/null || true)
  rpath=$(kubectl "${KUBECTL_ARGS[@]}" -n "$ns" get deploy "$deploy" -o jsonpath='{.spec.template.spec.containers[?(@.name=="prometheus-server")].readinessProbe.httpGet.path}' 2>/dev/null || true)
  if [[ "$lpath" != "/prometheus/-/healthy" || "$rpath" != "/prometheus/-/ready" ]]; then
    echo "[startup] Patching Prometheus probes to use route prefix..."
    kubectl -n "$ns" patch deploy "$deploy" --type='json' \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/1/livenessProbe/httpGet/path","value":"/prometheus/-/healthy"},{"op":"replace","path":"/spec/template/spec/containers/1/readinessProbe/httpGet/path","value":"/prometheus/-/ready"}]' || true
  else
    echo "[startup] Prometheus probes already use route prefix."
  fi
}

verify_dns_connectivity() {
  local ns=${1:-argocd}
  echo "[startup] Verifying cluster DNS + HTTPS egress (github.com)..."
  if ! kubectl "${KUBECTL_ARGS[@]}" get ns "$ns" >/dev/null 2>&1; then
    ns=default
  fi
  if kubectl "${KUBECTL_ARGS[@]}" run argocd-dns-check --rm -i --restart=Never -n "$ns" \
      --image=curlimages/curl:8.8.0 --command -- curl -sS --max-time 15 -I https://github.com >/dev/null; then
    echo "[startup] DNS and outbound HTTPS verified."
  else
    echo "[startup] WARNING: Unable to reach https://github.com from the cluster. Check node security group rules, route tables, or proxy settings." >&2
  fi
}

main() {
  # Ensure we run from repo root (script resides at repo root)
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  REPO_ROOT="${SCRIPT_DIR}"
  cd "${REPO_ROOT}"

  echo "[startup] === Phase 1: Provision infra (VPC + EKS) ==="
  tf_cmd init
  apply_cmd

  wait_for_nodes

  echo "[startup] === Phase 2: Install ALB controller via Terraform (ingress/) ==="
  # Pre-flight: ensure any pre-existing IngressClass 'alb' carries Helm ownership metadata
  if kubectl get ingressclass alb >/dev/null 2>&1; then
    echo "[startup] Reconciling ownership metadata on IngressClass/alb to avoid Helm adoption errors..."
    kubectl label ingressclass alb app.kubernetes.io/managed-by=Helm --overwrite || true
    kubectl annotate ingressclass alb \
      meta.helm.sh/release-name=aws-load-balancer-controller \
      meta.helm.sh/release-namespace=kube-system --overwrite || true
  fi
  pushd ingress >/dev/null
  tf_cmd init -upgrade
  apply_cmd
  popd >/dev/null

  # Verify controller deployment exists (kube-system/aws-load-balancer-controller)
  wait_for_deploy kube-system aws-load-balancer-controller
  # Verify webhook endpoints are backing the service before creating Ingresses
  wait_for_alb_webhook

  echo "[startup] === Phase 3: Deploy ArgoCD (argocd/) ==="
  if [[ -d "argocd" ]]; then
    # Resolve inputs from root outputs and env, to avoid prompts
    echo "[startup] Resolving ArgoCD module inputs from root outputs..."
    ROOT_CLUSTER=$(tf_cmd output -raw eks_cluster_name 2>/dev/null || echo "demo-eks-cluster")
    ROOT_SUBNETS=$(tf_cmd output -json public_subnet_ids 2>/dev/null || echo '[]')
    ARGO_REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}
    echo "  - cluster=${ROOT_CLUSTER} region=${ARGO_REGION} subnets=$(echo "$ROOT_SUBNETS" | tr -d '\n')"

  pushd argocd >/dev/null
  tf_cmd init -upgrade
  # Pass vars explicitly to avoid prompts
  tf_cmd apply -auto-approve \
      -var "eks_cluster_name=${ROOT_CLUSTER}" \
      -var "aws_region=${ARGO_REGION}" \
      -var "public_subnet_ids=$(echo "$ROOT_SUBNETS" | jq -c .)"
  echo "[startup] ArgoCD outputs:"
  tf_cmd output -json || true
  # Fallback: derive and print URL directly from the Ingress status
  HOST=$(kubectl -n ${var_namespace:-argocd} get ingress argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$HOST" ]; then
    echo "[startup] ArgoCD URL: http://$HOST/argocd"
  fi
  popd >/dev/null
  verify_dns_connectivity argocd
  else
    echo "[startup] argocd/ module not found; skipping ArgoCD deployment." >&2
  fi

  echo "[startup] Current TargetGroupBindings:"
  kubectl get targetgroupbindings -A || true

  cat <<TIP
[startup] Verify resources:
- kubectl -n argocd get ingress argocd -o wide
- kubectl get targetgroupbindings -A
- kubectl -n kube-system logs deploy/aws-load-balancer-controller -f

Argo CD:
- URL: Use terraform -chdir=argocd output argocd_ingress_url (or argocd_url)
- Admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
TIP
}

main "$@"
