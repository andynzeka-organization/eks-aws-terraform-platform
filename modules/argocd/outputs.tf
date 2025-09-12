output "service_hostname" {
  description = "ArgoCD Service external hostname or IP"
  # May be null when Service is ClusterIP (expected when exposed via shared ALB)
  value       = try(data.kubernetes_service.argocd_server.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "admin_password" {
  description = "ArgoCD initial admin password"
  value       = try(base64decode(data.kubernetes_secret.argocd_initial_admin.data["password"]), null)
  sensitive   = true
}
