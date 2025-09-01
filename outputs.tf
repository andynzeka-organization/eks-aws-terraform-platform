output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
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

# output "kube_prometheus_stack_helm_metadata" {
#   description = "Metadata Block outlining status of the deployed kube-prometheus-stack release."
#   value       = helm_release.kube_prometheus_stack.metadata
# }