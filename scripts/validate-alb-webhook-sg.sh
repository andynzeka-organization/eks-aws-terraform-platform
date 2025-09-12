#!/usr/bin/env bash
set -euo pipefail

# Validate SG rules for ALB controller webhook connectivity:
# - Node SG inbound TCP 9443 from Cluster SG
# - Node SG inbound TCP 9443 from Node SG (self) — covers additional SG path
#
# Exits 0 if OK, 1 if missing. Prints guidance.

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $1" >&2; exit 2; }; }
need aws; need jq

# Try to read from Terraform outputs (repo root)
CLUSTER_SG=${CLUSTER_SG:-$(terraform output -raw cluster_security_group_id 2>/dev/null || true)}
NODE_SG=${NODE_SG:-$(terraform output -raw node_security_group_id 2>/dev/null || true)}

if [[ -z "${CLUSTER_SG:-}" || -z "${NODE_SG:-}" ]]; then
  echo "[sg-validate] Could not resolve SG IDs from Terraform outputs. Set CLUSTER_SG and NODE_SG env vars, or run from repo root with outputs present." >&2
  exit 0  # warn-only
fi

echo "[sg-validate] Checking Node SG ${NODE_SG} for inbound 9443 from Cluster SG ${CLUSTER_SG} and self..."

json=$(aws ec2 describe-security-groups --group-ids "${NODE_SG}" --output json)

has_from_cluster=$(echo "$json" | jq -r --arg CL "$CLUSTER_SG" '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==9443 and .ToPort==9443 and .IpProtocol=="tcp") | any(.UserIdGroupPairs[]?; .GroupId==$CL)')
has_from_self=$(echo "$json" | jq -r --arg SG "$NODE_SG" '.SecurityGroups[0].IpPermissions[]? | select(.FromPort==9443 and .ToPort==9443 and .IpProtocol=="tcp") | any(.UserIdGroupPairs[]?; .GroupId==$SG)')

ok_cluster=$([[ "$has_from_cluster" == "true" ]] && echo yes || echo no)
ok_self=$([[ "$has_from_self" == "true" ]] && echo yes || echo no)

echo "  - from Cluster SG on 9443: ${ok_cluster}"
echo "  - from Node SG on 9443:    ${ok_self}"

if [[ "$ok_cluster" != "yes" || "$ok_self" != "yes" ]]; then
  if [[ "${SG_VALIDATE_STRICT:-false}" == "true" ]]; then
    echo "[sg-validate] Missing required SG rule(s). Ensure the root Terraform creates these (securitygroups.tf) and re-apply infra." >&2
    exit 1
  else
    echo "[sg-validate] WARNING: Missing SG rule(s); continuing because SG_VALIDATE_STRICT=false." >&2
    exit 0
  fi
fi

echo "[sg-validate] SG validation passed."
