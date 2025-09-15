output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.cluster_oidc_provider_arn
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the cluster (tagged for ELB)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the cluster"
  value       = module.vpc.private_subnet_ids
}

# Helpful for verifying ALB webhook connectivity paths
output "cluster_security_group_id" {
  description = "EKS Cluster Security Group ID (source for API server)"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "Node/Worker Security Group ID (destination for webhook on 9443)"
  value       = aws_security_group.eks_custom.id
}

output "grafana_password_command" {
  description = "Command to retrieve Grafana admin password from the cluster"
  value       = "kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
}
