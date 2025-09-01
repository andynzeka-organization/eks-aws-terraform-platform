output "argocd_server_hostname" {
  value       = module.argocd.service_hostname
  description = "ArgoCD LB hostname/IP"
}

output "argocd_admin_password" {
  value       = module.argocd.admin_password
  description = "ArgoCD admin password"
  sensitive   = true
}

