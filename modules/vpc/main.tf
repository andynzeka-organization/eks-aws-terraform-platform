locals {
  az_count = length(var.azs)
  cluster_discovery_tag = var.cluster_name_for_tag != null ? { "kubernetes.io/cluster/${var.cluster_name_for_tag}" = "shared" } : {}
}

resource "aws_vpc" "demo-vpc" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
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
depends_on = [ aws_vpc.demo-vpc ]
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
  
  depends_on = [ aws_vpc.demo-vpc ]
}

resource "aws_eip" "nat" {
  count = var.enable_nat_per_az ? local.az_count : 1

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-eip-${count.index}"
  })
  depends_on = [ aws_vpc.demo-vpc, aws_internet_gateway.igw ]
}

resource "aws_nat_gateway" "nat" {
  for_each = var.enable_nat_per_az ? { for k, s in aws_subnet.public : k => s } : { "0" = values(aws_subnet.public)[0] }

  allocation_id = var.enable_nat_per_az ? aws_eip.nat[tonumber(each.key)].id : aws_eip.nat[0].id
  subnet_id     = each.value.id

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })
  depends_on = [ aws_eip.nat, aws_internet_gateway.igw ]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
  depends_on = [ aws_internet_gateway.igw, aws_vpc.demo-vpc ]
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
  depends_on = [ aws_vpc.demo-vpc, aws_subnet.public ]
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.demo-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.enable_nat_per_az ? aws_nat_gateway.nat[each.key].id : aws_nat_gateway.nat["0"].id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-private-rt-${each.key}"
  })
  depends_on = [ aws_nat_gateway.nat, aws_vpc.demo-vpc ]
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
  
  depends_on = [ aws_vpc.demo-vpc, aws_subnet.private ]

}
