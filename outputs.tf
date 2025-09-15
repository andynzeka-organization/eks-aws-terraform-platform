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


# output "argocd_server_hostname" {
#   description = "ArgoCD Service external hostname or IP"
#   value       = coalesce(try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname, null), try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip, null))
# }

# output "argocd_admin_password" {
#   description = "ArgoCD initial admin password"
#   value       = try(base64decode(data.kubernetes_secret.argocd_initial_admin.data["password"]), null)
#   sensitive   = true
# }

# output "argo_cd_helm_metadata" {
#   description = "Metadata Block outlining status of the deployed release."
#   value       = helm_release.argocd.metadata
# }

# # Output Grafana LoadBalancer URL and Credentials
# output "grafana_admin_password" {
#   value       = "Admin123!" # or use a variable if you're managing it securely
#   description = "Grafana admin password"
# }

# output "grafana_service_url" {
#   value = try(
#     "http://" + data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname,
#     "Grafana LoadBalancer not yet assigned"
#   )
#   description = "Grafana UI LoadBalancer URL"
# }

output "grafana_password_command" {
  description = "Command to retrieve Grafana admin password from the cluster"
  value       = "kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
}

# output "kube_prometheus_stack_helm_metadata" {
#   description = "Metadata Block outlining status of the deployed kube-prometheus-stack release."
#   value       = helm_release.kube_prometheus_stack.metadata
# }
