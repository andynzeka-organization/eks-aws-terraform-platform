locals {
  az_count = length(var.azs)
  cluster_discovery_tag = var.cluster_name_for_tag != null ? { "kubernetes.io/cluster/${var.cluster_name_for_tag}" = var.cluster_discovery_tag_value } : {}
}

resource "aws_vpc" "demo-vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })

  # Best-effort ENI cleanup at destroy time to unblock VPC deletion
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
VPC_ID="${self.id}"
echo "[vpc-destroy] Best-effort ENI cleanup for VPC: $${VPC_ID}"

enis=$(aws ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values="$${VPC_ID}" \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Attachment:Attachment.AttachmentId,Status:Status}' \
  --output json 2>/dev/null || echo '[]')

echo "$enis" | jq -c '.[]' 2>/dev/null | while read -r item; do
  id=$(echo "$item" | jq -r '.Id')
  att=$(echo "$item" | jq -r '.Attachment // empty')
  st=$(echo "$item" | jq -r '.Status // empty')
  [[ -z "$id" || "$id" == "null" ]] && continue
  if [[ -n "$att" && "$att" != "null" ]]; then
    echo "  - detaching ENI $id (attachment $att, status: $st)" && aws ec2 detach-network-interface --attachment-id "$att" --force >/dev/null 2>&1 || true
    sleep 2
  fi
  echo "  - deleting ENI $id" && aws ec2 delete-network-interface --network-interface-id "$id" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] ENI cleanup complete (best effort)."

# Additional best-effort cleanup to unblock VPC deletion
echo "[vpc-destroy] Deleting ELBv2 resources in VPC (best effort)..."
lbs=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$${VPC_ID}'].[LoadBalancerArn]" --output text 2>/dev/null || true)
for lb in $lbs; do
  [[ -z "$lb" ]] && continue
  echo "  - deleting LB: $lb" && aws elbv2 delete-load-balancer --load-balancer-arn "$lb" >/dev/null 2>&1 || true
done
echo "[vpc-destroy] Deleting Target Groups in VPC (best effort)..."
tgs=$(aws elbv2 describe-target-groups --query "TargetGroups[?VpcId=='$${VPC_ID}'].[TargetGroupArn]" --output text 2>/dev/null || true)
for tg in $tgs; do
  [[ -z "$tg" ]] && continue
  echo "  - deleting TG: $tg" && aws elbv2 delete-target-group --target-group-arn "$tg" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] Deleting ALB-created Security Groups (tagged) in VPC (best effort)..."
sgs_tagged=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$${VPC_ID} Name=tag:elbv2.k8s.aws/cluster,Values='*' --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || true)
for sg in $sgs_tagged; do
  [[ -z "$sg" ]] && continue
  echo "  - deleting ALB SG: $sg" && aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] Deleting non-default Security Groups in VPC (best effort)..."
sgs_nontag=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$${VPC_ID} --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)
for sg in $sgs_nontag; do
  [[ -z "$sg" ]] && continue
  echo "  - deleting SG: $sg" && aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] Deleting non-main Route Tables in VPC (best effort)..."
rts=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$${VPC_ID} --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' --output text 2>/dev/null || true)
for rt in $rts; do
  [[ -z "$rt" ]] && continue
  assocs=$(aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text 2>/dev/null || true)
  for a in $assocs; do
    [[ -z "$a" ]] && continue
    echo "  - disassociating RT assoc: $a" && aws ec2 disassociate-route-table --association-id "$a" >/dev/null 2>&1 || true
  done
  echo "  - deleting RT: $rt" && aws ec2 delete-route-table --route-table-id "$rt" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] Deleting non-default Network ACLs in VPC (best effort)..."
nacls=$(aws ec2 describe-network-acls --filters Name=vpc-id,Values=$${VPC_ID} --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' --output text 2>/dev/null || true)
for n in $nacls; do
  [[ -z "$n" ]] && continue
  echo "  - deleting NACL: $n" && aws ec2 delete-network-acl --network-acl-id "$n" >/dev/null 2>&1 || true
done

echo "[vpc-destroy] Re-associating default DHCP options (best effort)..."
default_dhcp=$(aws ec2 describe-dhcp-options --filters Name=default,Values=true --query 'DhcpOptions[0].DhcpOptionsId' --output text 2>/dev/null || echo "")
if [[ -n "$default_dhcp" && "$default_dhcp" != "None" ]]; then
  aws ec2 associate-dhcp-options --dhcp-options-id "$default_dhcp" --vpc-id "$${VPC_ID}" >/dev/null 2>&1 || true
fi
EOT
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo-vpc.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
  depends_on = [ aws_vpc.demo-vpc ]
}

resource "aws_subnet" "public" {
  for_each = { for idx, az in var.azs : tostring(idx) => {
    az   = az
    cidr = var.public_subnet_cidrs[idx]
  } }

  vpc_id                  = aws_vpc.demo-vpc.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.value.az}"
    Tier = "public"
    "kubernetes.io/role/elb" = "1"
  }, local.cluster_discovery_tag)
depends_on = [ aws_internet_gateway.igw ]

  # Pre-destroy helper: best-effort cleanup of ENIs in this subnet to unblock deletion
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
SUBNET_ID="${self.id}"
echo "[subnet-destroy] Cleaning ENIs in subnet $SUBNET_ID ..."
enis=$(aws ec2 describe-network-interfaces \
  --filters Name=subnet-id,Values="$SUBNET_ID" \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Attachment:Attachment.AttachmentId,Status:Status}' \
  --output json 2>/dev/null || echo '[]')
echo "$enis" | jq -c '.[]' 2>/dev/null | while read -r item; do
  id=$(echo "$item" | jq -r '.Id')
  att=$(echo "$item" | jq -r '.Attachment // empty')
  st=$(echo "$item" | jq -r '.Status // empty')
  [[ -z "$id" || "$id" == "null" ]] && continue
  if [[ -n "$att" && "$att" != "null" ]]; then
    echo "  - detaching ENI $id (attachment $att, status: $st)" && aws ec2 detach-network-interface --attachment-id "$att" --force >/dev/null 2>&1 || true
    sleep 2
  fi
  echo "  - deleting ENI $id" && aws ec2 delete-network-interface --network-interface-id "$id" >/dev/null 2>&1 || true
done
echo "[subnet-destroy] ENI cleanup complete for $SUBNET_ID."
EOT
  }
}

resource "aws_subnet" "private" {
  for_each = { for idx, az in var.azs : tostring(idx) => {
    az   = az
    cidr = var.private_subnet_cidrs[idx]
  } }

  vpc_id            = aws_vpc.demo-vpc.id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.value.az}"
    Tier = "private"
    "kubernetes.io/role/internal-elb" = "1"
  }, local.cluster_discovery_tag)
  
  depends_on = [ aws_internet_gateway.igw ]

  # Pre-destroy helper: best-effort cleanup of ENIs in this subnet to unblock deletion
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail
SUBNET_ID="${self.id}"
echo "[subnet-destroy] Cleaning ENIs in subnet $SUBNET_ID ..."
enis=$(aws ec2 describe-network-interfaces \
  --filters Name=subnet-id,Values="$SUBNET_ID" \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Attachment:Attachment.AttachmentId,Status:Status}' \
  --output json 2>/dev/null || echo '[]')
echo "$enis" | jq -c '.[]' 2>/dev/null | while read -r item; do
  id=$(echo "$item" | jq -r '.Id')
  att=$(echo "$item" | jq -r '.Attachment // empty')
  st=$(echo "$item" | jq -r '.Status // empty')
  [[ -z "$id" || "$id" == "null" ]] && continue
  if [[ -n "$att" && "$att" != "null" ]]; then
    echo "  - detaching ENI $id (attachment $att, status: $st)" && aws ec2 detach-network-interface --attachment-id "$att" --force >/dev/null 2>&1 || true
    sleep 2
  fi
  echo "  - deleting ENI $id" && aws ec2 delete-network-interface --network-interface-id "$id" >/dev/null 2>&1 || true
done
echo "[subnet-destroy] ENI cleanup complete for $SUBNET_ID."
EOT
  }
}

## NAT resources disabled (nodes will use public subnets with public IPs)

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
  depends_on = [ aws_internet_gateway.igw ]
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
  depends_on = [ aws_subnet.public ]
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id = aws_vpc.demo-vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${each.key}"
  })
  depends_on = [ aws_internet_gateway.igw ]
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
  
  depends_on = [ aws_subnet.private ]
}
