output "service_hostname" {
  description = "ArgoCD Service external hostname or IP"
  value       = coalesce(try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname, null), try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].ip, null))
}

output "admin_password" {
  description = "ArgoCD initial admin password"
  value       = try(base64decode(data.kubernetes_secret.argocd_initial_admin.data["password"]), null)
  sensitive   = true
}
