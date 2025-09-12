#!/usr/bin/env bash
set -euo pipefail

# Force-clean common blockers so a VPC can be deleted.
# This script removes ALBs/NLBs, Target Groups, VPC Endpoints, NAT Gateways,
# Internet Gateways, dangling ENIs, non-main Route Tables, non-default SGs, and non-default NACLs
# for the specified VPC, then attempts to delete the VPC.
#
# Requirements: awscli, jq
# Usage:
#   export AWS_PROFILE=... AWS_REGION=...
#   ./scripts/force-delete-vpc.sh <vpc-id>

if ! command -v aws >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: Requires awscli and jq in PATH" >&2
  exit 1
fi

VPC_ID=${1:-}
if [[ -z ${VPC_ID} ]]; then
  echo "Usage: $0 <vpc-id>" >&2
  exit 1
fi

echo "[force-delete-vpc] Target VPC: ${VPC_ID} (region: ${AWS_REGION:-<default>}, profile: ${AWS_PROFILE:-<default>})"

retry() {
  local tries=$1; shift
  local delay=${1:-3}; shift || true
  local i=0
  until "$@"; do
    i=$((i+1));
    if (( i >= tries )); then return 1; fi
    sleep "$delay"
  done
}

delete_elbv2_load_balancers() {
  echo "[force-delete-vpc] Deleting ELBv2 load balancers in VPC..."
  local lbs ids
  lbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='${VPC_ID}'].[LoadBalancerArn,LoadBalancerName]" --output json)
  ids=$(echo "$lbs" | jq -r '.[].[0]')
  if [[ -z "$ids" ]]; then echo "  none"; return; fi
  echo "$lbs" | jq -r '.[] | @tsv' | while IFS=$'\t' read -r arn name; do
    echo "  deleting LB: $name ($arn)" && aws elbv2 delete-load-balancer --load-balancer-arn "$arn" || true
  done
  echo "  waiting for LBs to disappear..."
  sleep 10
}

delete_elbv2_target_groups() {
  echo "[force-delete-vpc] Deleting ELBv2 target groups in VPC..."
  local tgs ids
  tgs=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='${VPC_ID}'].[TargetGroupArn,TargetGroupName]" --output json || echo '[]')
  ids=$(echo "$tgs" | jq -r '.[].[0]')
  if [[ -z "$ids" ]]; then echo "  none"; return; fi
  echo "$tgs" | jq -r '.[] | @tsv' | while IFS=$'\t' read -r arn name; do
    echo "  deleting TG: $name ($arn)" && aws elbv2 delete-target-group --target-group-arn "$arn" || true
  done
}

delete_vpc_endpoints() {
  echo "[force-delete-vpc] Deleting VPC endpoints..."
  local eps ids
  eps=$(aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=${VPC_ID} --query 'VpcEndpoints[].VpcEndpointId' --output json)
  ids=$(echo "$eps" | jq -r '.[]')
  if [[ -z "$ids" ]]; then echo "  none"; return; fi
  echo "$ids" | xargs -r aws ec2 delete-vpc-endpoints --vpc-endpoint-ids || true
}

delete_nat_gateways() {
  echo "[force-delete-vpc] Deleting NAT gateways (this can take 10–20+ minutes)..."
  local ngw_ids
  ngw_ids=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="${VPC_ID}" --query "NatGateways[].NatGatewayId" --output text 2>/dev/null || true)
  if [[ -z "${ngw_ids:-}" || "${ngw_ids}" == "None" ]]; then echo "  none"; return; fi
  for id in $ngw_ids; do
    echo "  deleting NAT GW: $id" && aws ec2 delete-nat-gateway --nat-gateway-id "$id" || true
  done
  echo "  waiting for NAT gateways to delete..."
  for i in {1..90}; do
    pending=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="${VPC_ID}" --query "length(NatGateways[?State!='deleted'])" --output text 2>/dev/null || echo 0)
    if [[ "$pending" == "0" || "$pending" == "None" ]]; then
      echo "  NAT gateways deleted."
      break
    fi
    printf "  still deleting NAT gateways… (%s remaining)\n" "$pending"
    sleep 10
  done
}

detach_delete_igw() {
  echo "[force-delete-vpc] Detaching and deleting internet gateways..."
  local igw_ids
  igw_ids=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=${VPC_ID} --query 'InternetGateways[].InternetGatewayId' --output json | jq -r '.[]')
  if [[ -z "$igw_ids" ]]; then echo "  none"; return; fi
  for id in $igw_ids; do
    echo "  detaching IGW: $id" && aws ec2 detach-internet-gateway --internet-gateway-id "$id" --vpc-id "$VPC_ID" || true
    echo "  deleting  IGW: $id" && aws ec2 delete-internet-gateway --internet-gateway-id "$id" || true
  done
}

delete_route_tables() {
  echo "[force-delete-vpc] Deleting non-main route tables..."
  local rts
  rts=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=${VPC_ID} --output json)
  echo "$rts" | jq -c '.RouteTables[]' | while read -r rt; do
    local rtb_id is_main
    rtb_id=$(echo "$rt" | jq -r '.RouteTableId')
    is_main=$(echo "$rt" | jq -r '.Associations[]? | select(.Main==true) | .Main' || true)
    if [[ "$is_main" == "true" ]]; then
      echo "  skipping main RT: $rtb_id"
      continue
    fi
    # disassociate non-main associations
    echo "$rt" | jq -r '.Associations[]? | select(.Main!=true) | .RouteTableAssociationId' | while read -r assoc; do
      [[ -z "$assoc" ]] || { echo "  disassociate $assoc"; aws ec2 disassociate-route-table --association-id "$assoc" || true; }
    done
    echo "  delete RT: $rtb_id" && aws ec2 delete-route-table --route-table-id "$rtb_id" || true
  done
}

delete_security_groups() {
  echo "[force-delete-vpc] Deleting non-default security groups..."
  local sgs
  sgs=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=${VPC_ID} --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' --output json)
  echo "$sgs" | jq -r '.[] | @tsv' | while IFS=$'\t' read -r sg_id name; do
    echo "  delete SG: $name ($sg_id)" && aws ec2 delete-security-group --group-id "$sg_id" || true
  done
}

delete_network_acls() {
  echo "[force-delete-vpc] Deleting non-default network ACLs..."
  local acls
  acls=$(aws ec2 describe-network-acls --filters Name=vpc-id,Values=${VPC_ID} --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output json | jq -r '.[]')
  if [[ -z "$acls" ]]; then echo "  none"; return; fi
  for id in $acls; do
    echo "  delete NACL: $id" && aws ec2 delete-network-acl --network-acl-id "$id" || true
  done
}

delete_enis() {
  echo "[force-delete-vpc] Deleting ENIs (detach if needed)..."
  local enis
  enis=$(aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Attachment:Attachment.AttachmentId}' --output json)
  echo "$enis" | jq -c '.[]' | while read -r eni; do
    local id att
    id=$(echo "$eni" | jq -r '.Id')
    att=$(echo "$eni" | jq -r '.Attachment // empty')
    if [[ -n "$att" && "$att" != "null" ]]; then
      echo "  detach ENI: $id (attachment: $att)" && aws ec2 detach-network-interface --attachment-id "$att" --force || true
      sleep 2
    fi
    echo "  delete ENI: $id" && aws ec2 delete-network-interface --network-interface-id "$id" || true
  done
}

delete_flow_logs() {
  echo "[force-delete-vpc] Deleting VPC flow logs..."
  local fl
  fl=$(aws ec2 describe-flow-logs --filter Name=resource-id,Values=${VPC_ID} --query 'FlowLogs[].FlowLogId' --output text 2>/dev/null || true)
  if [[ -z "${fl:-}" || "${fl}" == "None" ]]; then echo "  none"; return; fi
  for id in $fl; do
    echo "  delete FlowLog: $id" && aws ec2 delete-flow-logs --flow-log-ids "$id" || true
  done
}

disassociate_dhcp_options() {
  echo "[force-delete-vpc] Associating default DHCP options to detach custom set..."
  aws ec2 associate-dhcp-options --dhcp-options-id default --vpc-id "${VPC_ID}" >/dev/null 2>&1 || true
}

echo "[force-delete-vpc] Starting dependency cleanup..."
delete_elbv2_load_balancers
delete_elbv2_target_groups
delete_vpc_endpoints
delete_nat_gateways
detach_delete_igw
delete_enis
delete_flow_logs
delete_route_tables
delete_security_groups
delete_network_acls
disassociate_dhcp_options

echo "[force-delete-vpc] Attempting VPC delete: ${VPC_ID}"
if aws ec2 delete-vpc --vpc-id "$VPC_ID"; then
  echo "[force-delete-vpc] VPC deletion requested successfully."
else
  echo "[force-delete-vpc] VPC delete failed. Re-run script after a few minutes; some AWS resources (e.g., NAT) take time to purge." >&2
  exit 2
fi
