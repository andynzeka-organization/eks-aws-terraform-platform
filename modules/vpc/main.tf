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
