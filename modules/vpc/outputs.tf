output "vpc_id" {
  value = aws_vpc.demo-vpc.id
}

output "vpc_cidr_block" {
  value = aws_vpc.demo-vpc.cidr_block
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "azs" {
  value = var.azs
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_ids" {
  value = { for k, v in aws_route_table.private : k => v.id }
}

output "nat_gateway_ids" {
  value = [for k, v in aws_nat_gateway.nat : v.id]
}

