#############################################
# Preflight: Validate annotated subnets (warn)
#############################################

locals {
  # Pull controller VPC and intended public subnets from remote state
  controller_vpc_id  = try(data.terraform_remote_state.infra.outputs.vpc_id, "")
  annotated_subnets  = try(data.terraform_remote_state.infra.outputs.public_subnet_ids, [])
}

resource "null_resource" "validate_ingress_subnets" {
  count = var.enable_ingress_preflight ? 1 : 0

  triggers = {
    always_run = timestamp()
    vpc_id     = local.controller_vpc_id
    subnets    = join(",", local.annotated_subnets)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
VPC_ID="${self.triggers.vpc_id}"
SUBNETS_STR="${self.triggers.subnets}"

echo "[preflight] Validating annotated subnets against controller VPC $${VPC_ID} (warn-only)..."
if [[ -z "$${VPC_ID}" || -z "$${SUBNETS_STR}" ]]; then
  echo "[preflight] Skipping: missing VPC or subnet outputs from remote state." >&2
  exit 0
fi

IFS=',' read -r -a SUBNETS <<< "$${SUBNETS_STR}"
for subnet_id in "$${SUBNETS[@]}"; do
  subnet_id=$(echo "$subnet_id" | xargs)
  [[ -z "$subnet_id" ]] && continue
  vpc=$(aws ec2 describe-subnets --subnet-ids "$subnet_id" --query 'Subnets[0].VpcId' --output text 2>/dev/null || echo "<none>")
  if [[ "$vpc" != "$${VPC_ID}" ]]; then
    echo "[preflight] ⚠ Subnet $subnet_id is not in controller VPC ($${VPC_ID}). Actual: $${vpc}" >&2
  fi
done
echo "[preflight] ✅ Preflight subnet check complete."
EOT
  }
}

#############################################
# Preflight: Wait for ALB webhook endpoints
#############################################

resource "null_resource" "alb_webhook_ready" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
echo "[preflight] Waiting for ALB controller webhook endpoints to be ready..."
START=$(date +%s)
TIMEOUT=$${TIMEOUT:-600}
SLEEP=$${SLEEP:-5}
while true; do
  if kubectl -n kube-system get svc aws-load-balancer-webhook-service >/dev/null 2>&1; then
    addrs=$(kubectl -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)
    ports=$(kubectl -n kube-system get endpoints aws-load-balancer-webhook-service -o jsonpath='{.subsets[*].ports[*].port}' 2>/dev/null || true)
    echo "  - webhook endpoints IPs: $${addrs:-<none>} ports: $${ports:-<none>}"
    if [[ -n "$${addrs:-}" && "$${ports:-}" == *"9443"* ]]; then
      echo "[preflight] ✅ ALB controller webhook endpoints are ready."
      break
    fi
  fi
  now=$(date +%s)
  if (( now - START > TIMEOUT )); then
    echo "[preflight] ❌ Timed out waiting for ALB webhook endpoints. If installs still fail with webhook timeouts, ensure a security group rule allows TCP 9443 from the EKS cluster security group to your worker node security group(s)." >&2
    exit 1
  fi
  sleep "$SLEEP"
done
EOT
  }
}
