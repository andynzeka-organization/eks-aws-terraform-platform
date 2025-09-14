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

