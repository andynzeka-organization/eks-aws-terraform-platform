#!/usr/bin/env bash
set -euo pipefail

# Destroys app Helm releases and ALB-related Kubernetes resources safely,
# then destroys Terraform stacks in the correct order.
# WARNING: This is destructive. It will:
#  - Destroy platform apps Terraform (Helm releases) first
#  - Delete ALL Ingress resources in the cluster
#  - Wait for all TargetGroupBindings to be removed (avoids orphan ALBs)
#  - Uninstall the AWS Load Balancer Controller Helm release
#  - Delete the IngressClass and RBAC manifests added by this repo
#  - Remove remaining ArgoCD CRDs (applications, applicationsets, appprojects)
#  - Run `terraform destroy -auto-approve` in `ingress/` and in repo root
#
# Env vars:
#  - RELEASE_NAME (default: aws-load-balancer-controller)
#  - RELEASE_NAMESPACE (default: kube-system)
#  - TIMEOUT (seconds, default: 1200)
#  - SLEEP (seconds between checks, default: 10)
#  - FORCE (true|false, default: false)  # set true to skip interactive confirmation
#  - FAST_ELB_CLEAN (true|false, default: true)  # if true, skip long waits and force-delete ALBs/TGs in VPC
#  - ELB_ONLY (true|false, default: false)       # if true, only purge ALBs/TGs/ALB SGs, then exit
#  - VPC_ID (optional)                           # VPC to target when purging ELBv2 resources (recommended)

RELEASE_NAME=${RELEASE_NAME:-aws-load-balancer-controller}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-kube-system}
TIMEOUT=${TIMEOUT:-1200}
SLEEP=${SLEEP:-10}
FORCE=${FORCE:-false}
FAST_ELB_CLEAN=${FAST_ELB_CLEAN:-true}
ELB_ONLY=${ELB_ONLY:-false}
# Extra args for kubectl to avoid long hangs
KUBECTL_ARGS=(--request-timeout=10s)
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

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
  # Prefer explicit VPC_ID env if provided
  if [[ -n "${VPC_ID:-}" ]]; then
    echo "${VPC_ID}"
    return 0
  fi
  # Avoid noisy Terraform output warnings by suppressing all output
  local v
  v=$(terraform output -raw vpc_id >/dev/null 2>&1 || true)
  if [[ -n "${v:-}" ]]; then
    echo "${v}"
    return 0
  fi
  v=$(tf_cmd output -raw vpc_id >/dev/null 2>&1 || true)
  if [[ -n "${v:-}" ]]; then
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

delete_elbv2_in_vpc() {
  local vpc_id="$1"
  echo "[destroy] FAST_ELB_CLEAN=true -> deleting ALBs/TargetGroups in VPC ${vpc_id}..."
  # Delete LBs first
  local lbs
  lbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${vpc_id}'].[LoadBalancerArn,LoadBalancerName]" --output json 2>/dev/null || echo '[]')
  echo "$lbs" | jq -r '.[] | @tsv' 2>/dev/null | while IFS=$'\t' read -r arn name; do
    [[ -z "$arn" ]] && continue
    echo "  - deleting LB: ${name:-$arn}"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn" >/dev/null 2>&1 || true
  done
  # Then delete Target Groups
  local tgs
  tgs=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='${vpc_id}'].[TargetGroupArn,TargetGroupName]" --output json 2>/dev/null || echo '[]')
  echo "$tgs" | jq -r '.[] | @tsv' 2>/dev/null | while IFS=$'\t' read -r arn name; do
    [[ -z "$arn" ]] && continue
    echo "  - deleting TG: ${name:-$arn}"
    aws elbv2 delete-target-group --target-group-arn "$arn" >/dev/null 2>&1 || true
  done
}

# Delete ELBv2 resources by cluster tag (fallback when VPC ID is unknown)
delete_elbv2_by_cluster_tag() {
  local cluster_name="$1" region="$2"
  echo "[destroy] FAST_ELB_CLEAN=true -> deleting ALBs/TargetGroups tagged for cluster ${cluster_name} in ${region}..."
  # Delete LBs first
  local lbs
  lbs=$(aws elbv2 describe-load-balancers --region "${region}" --query "LoadBalancers[?contains(Tags[?Key=='kubernetes.io/cluster/${cluster_name}'].Value | [0], 'owned')].[LoadBalancerArn,LoadBalancerName]" --output json 2>/dev/null || echo '[]')
  echo "$lbs" | jq -r '.[] | @tsv' 2>/dev/null | while IFS=$'\t' read -r arn name; do
    [[ -z "$arn" ]] && continue
    echo "  - deleting LB: ${name:-$arn}"
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn" --region "${region}" >/dev/null 2>&1 || true
  done
  # Then delete Target Groups with the same tag
  local tgs
  tgs=$(aws elbv2 describe-target-groups --region "${region}" --query "TargetGroups[?contains(Tags[?Key=='kubernetes.io/cluster/${cluster_name}'].Value | [0], 'owned')].[TargetGroupArn,TargetGroupName]" --output json 2>/dev/null || echo '[]')
  echo "$tgs" | jq -r '.[] | @tsv' 2>/dev/null | while IFS=$'\t' read -r arn name; do
    [[ -z "$arn" ]] && continue
    echo "  - deleting TG: ${name:-$arn}"
    aws elbv2 delete-target-group --target-group-arn "$arn" --region "${region}" >/dev/null 2>&1 || true
  done

  # Attempt to delete ALB-created SGs tagged for this cluster
  local sgs
  sgs=$(aws ec2 describe-security-groups --region "${region}" \
    --filters Name=tag:elbv2.k8s.aws/cluster,Values="${cluster_name}" \
    --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)
  for sg in $sgs; do
    [[ -z "$sg" ]] && continue
    echo "  - deleting SG: $sg (tagged elbv2.k8s.aws/cluster=${cluster_name})"
    aws ec2 delete-security-group --region "${region}" --group-id "$sg" >/dev/null 2>&1 || true
  done
}

# Best-effort: delete ALB-created security groups in VPC
delete_alb_sgs_in_vpc() {
  local vpc_id="$1"
  echo "[destroy] Deleting ALB-related security groups in VPC ${vpc_id}..."
  local json
  json=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="${vpc_id}" --output json 2>/dev/null || echo '{}')
  # Select SGs tagged for k8s ALB or with a k8s-ish name/description
  echo "$json" | jq -r '
    (.SecurityGroups // [])
    | map(select((.Tags // []) | any(.Key == "elbv2.k8s.aws/cluster"))
           or (.GroupName | test("^k8s-"))
           or ((.Description // "") | test("kubernetes|k8s|Load Balancer", "i")))
    | .[] | .GroupId' 2>/dev/null | while read -r sg; do
      [[ -z "$sg" ]] && continue
      echo "  - deleting SG: $sg"
      aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
    done
}

# Print a quick blockers report for the VPC
report_vpc_blockers() {
  local vpc_id="$1"
  echo "[destroy] Blockers report for VPC ${vpc_id}:"
  aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${vpc_id}'].[LoadBalancerName,State.Code]" --output table 2>/dev/null || true
  aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='${vpc_id}'].[TargetGroupName,TargetGroupArn]" --output table 2>/dev/null || true
  aws ec2 describe-security-groups --filters Name=vpc-id,Values="${vpc_id}" --query "SecurityGroups[?length(Tags[?Key=='elbv2.k8s.aws/cluster'])>\`0\`].[GroupId,GroupName]" --output table 2>/dev/null || true
  aws ec2 describe-network-interfaces --filters Name=vpc-id,Values="${vpc_id}" --query "NetworkInterfaces[?Status=='in-use'].[NetworkInterfaceId,Description]" --output table 2>/dev/null || true
}

# Best-effort check whether the EKS cluster exists
cluster_exists() {
  local cluster_name="$1" region="$2"
  aws eks describe-cluster --name "${cluster_name}" --region "${region}" >/dev/null 2>&1
}

disable_alb_webhooks_if_unavailable() {
  # If the ALB controller webhook is unreachable, ingress deletes will hang.
  # Try a short wait for the controller; if not available, delete webhook configs.
  local wait_seconds=60
  echo "[destroy] Checking ALB webhooks availability..."
  if kubectl -n kube-system get deploy aws-load-balancer-controller >/dev/null 2>&1; then
    echo "[destroy] Waiting up to ${wait_seconds}s for aws-load-balancer-controller to be Available..."
    if ! kubectl -n kube-system wait --for=condition=available deployment/aws-load-balancer-controller --timeout=${wait_seconds}s >/dev/null 2>&1; then
      echo "[destroy] Controller not Available; removing webhook configurations to unblock deletes."
      for kind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
        for w in $(kubectl get ${kind} -o name 2>/dev/null | grep -E 'elbv2\.k8s\.aws|aws-load-balancer' || true); do
          echo "  - deleting $w"
          kubectl delete "$w" --ignore-not-found >/dev/null 2>&1 || true
        done
      done
    else
      echo "[destroy] ALB controller is Available; proceeding."
    fi
  else
    echo "[destroy] ALB controller deployment not found; removing webhook configurations if present."
    for kind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
      for w in $(kubectl get ${kind} -o name 2>/dev/null | grep -E 'elbv2\.k8s\.aws|aws-load-balancer' || true); do
        echo "  - deleting $w"
        kubectl delete "$w" --ignore-not-found >/dev/null 2>&1 || true
      done
    done
  fi
}

destroy_argocd_module() {
  if [[ -d "${REPO_ROOT}/argocd" ]]; then
    # Skip if the cluster no longer exists; providers/data sources will fail
    local region cluster
    region=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}
    cluster=${CLUSTER_NAME:-demo-eks-cluster}
    if ! cluster_exists "${cluster}" "${region}"; then
      echo "[destroy] Skipping argocd/ destroy: cluster ${cluster} not found in ${region}."
      return 0
    fi
    echo "[destroy] Destroying ArgoCD module (argocd/)..."
    pushd "${REPO_ROOT}/argocd" >/dev/null
    tf_cmd init -upgrade || true
    # Resolve inputs from root to avoid prompts during destroy
    ROOT_CLUSTER=$(tf_cmd -chdir="${REPO_ROOT}" output -raw eks_cluster_name 2>/dev/null || echo "${cluster}")
    ROOT_SUBNETS=$(tf_cmd -chdir="${REPO_ROOT}" output -json public_subnet_ids 2>/dev/null || echo '[]')
    tf_cmd destroy -auto-approve \
      -var "eks_cluster_name=${ROOT_CLUSTER}" \
      -var "aws_region=${region}" \
      -var "public_subnet_ids=$(echo "$ROOT_SUBNETS" | jq -c .)" || true
    popd >/dev/null
    echo "[destroy] Deleting ArgoCD CRDs..."
    kubectl "${KUBECTL_ARGS[@]}" delete crd \
      applications.argoproj.io \
      applicationsets.argoproj.io \
      appprojects.argoproj.io \
      --ignore-not-found >/dev/null 2>&1 || true
  fi
}

main() {
  confirm

  # Ensure we run from repo root (script resides in scripts/)
  cd "${REPO_ROOT}"

  # Proactively destroy ArgoCD to remove its Ingress/Services first
  destroy_argocd_module

  # Only run kubectl/helm operations if the cluster exists
  REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}
  CLUSTER=${CLUSTER_NAME:-demo-eks-cluster}
  if cluster_exists "${CLUSTER}" "${REGION}"; then
    disable_alb_webhooks_if_unavailable || true
    echo "[destroy] Deleting all Ingress resources cluster-wide..."
    kubectl "${KUBECTL_ARGS[@]}" delete ingress --all --all-namespaces --wait=false 2>/dev/null || true

    echo "[destroy] Stripping ingress finalizers to prevent hanging deletions..."
    while IFS= read -r ing; do
      [ -n "$ing" ] || continue
      echo "  - patching $ing"
      kubectl "${KUBECTL_ARGS[@]}" patch "$ing" --type=json -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
    done < <(kubectl "${KUBECTL_ARGS[@]}" get ingress -A -o name 2>/dev/null || true)

    echo "[destroy] Uninstalling Helm release ${RELEASE_NAME} in ${RELEASE_NAMESPACE}..."
    helm uninstall "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" >/dev/null 2>&1 || true
  else
    echo "[destroy] Cluster ${CLUSTER} not found in ${REGION}; skipping kubectl/helm cleanup."
  fi

  if [[ "${FAST_ELB_CLEAN}" == "true" ]]; then
    VPC_ID_RESOLVED=$(resolve_vpc_id || true)
    if [[ -n "${VPC_ID_RESOLVED}" ]]; then
      delete_elbv2_in_vpc "${VPC_ID_RESOLVED}"
      delete_alb_sgs_in_vpc "${VPC_ID_RESOLVED}"
      wait_for_elbv2_cleanup "${VPC_ID_RESOLVED}"
      report_vpc_blockers "${VPC_ID_RESOLVED}"
    else
      echo "[destroy] FAST_ELB_CLEAN: could not resolve VPC ID; attempting tag-based cleanup." >&2
      delete_elbv2_by_cluster_tag "${CLUSTER}" "${REGION}" || true
    fi
  else
    wait_for_tgbs
    # Wait for AWS ELBv2 resources (ALBs/Target Groups) to disappear from the VPC
    VPC_ID_RESOLVED=$(resolve_vpc_id || true)
    if [[ -n "${VPC_ID_RESOLVED}" ]]; then
      wait_for_elbv2_cleanup "${VPC_ID_RESOLVED}"
    else
      echo "[destroy] Skipping ELBv2 wait: could not resolve VPC ID (set VPC_ID env to force)." >&2
    fi
  fi

  # If ELB_ONLY is requested, stop here after ELB cleanup
  if [[ "${ELB_ONLY}" == "true" ]]; then
    echo "[destroy] ELB_ONLY=true: finished ELB/TG/SG cleanup. Exiting without Terraform destroys."
    exit 0
  fi

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
    # Skip if cluster is gone to avoid provider/data source failures
    if cluster_exists "${CLUSTER}" "${REGION}"; then
      echo "[destroy] Terraform destroy in ingress/ ..."
      (cd ingress && tf_cmd destroy -auto-approve) || true
    else
      echo "[destroy] Skipping ingress/ destroy: cluster ${CLUSTER} not found in ${REGION}."
    fi
  fi

  # Terraform destroy in repo root (retry with forced VPC cleanup if needed)
  echo "[destroy] Terraform destroy in repo root ..."
  if ! tf_cmd destroy -auto-approve; then
    echo "[destroy] Root destroy failed. Attempting forced VPC dependency cleanup..." >&2
    VPC_ID_RESOLVED=$(resolve_vpc_id || true)
    if [[ -n "${VPC_ID_RESOLVED}" && -x "${REPO_ROOT}/scripts/force-delete-vpc.sh" ]]; then
      "${REPO_ROOT}/scripts/force-delete-vpc.sh" "${VPC_ID_RESOLVED}" || true
      echo "[destroy] Retrying root Terraform destroy after VPC cleanup..."
      tf_cmd destroy -auto-approve || true
    else
      # Fall back to cluster-tag-based deletion if VPC is unknown
      echo "[destroy] Could not resolve VPC ID. Deleting ELBv2 resources by cluster tag..." >&2
      delete_elbv2_by_cluster_tag "${CLUSTER}" "${REGION}" || true
      echo "[destroy] Retrying root Terraform destroy after ELBv2 tag-based cleanup..."
      tf_cmd destroy -auto-approve || true
    fi
  fi

  echo "[destroy] Complete."
}

main "$@"
