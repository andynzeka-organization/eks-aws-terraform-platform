output "argocd_server_hostname" {
  value       = module.argocd.service_hostname
  description = "ArgoCD LB hostname/IP"
}

output "argocd_admin_password" {
  value       = module.argocd.admin_password
  description = "ArgoCD admin password"
  sensitive   = true
}

output "post_install_summary" {
  description = "Human-friendly summary for ArgoCD access"
  value = <<EOT
ArgoCD
- URL: ${coalesce(module.argocd.service_hostname, "<pending>") != null ? "https://" : ""}${coalesce(module.argocd.service_hostname, "<pending>")}
- Username: admin
- Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
- If no external address: kubectl -n argocd port-forward svc/argocd-server 8080:443
EOT
}
