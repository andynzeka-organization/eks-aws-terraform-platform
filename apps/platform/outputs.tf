output "argocd_server_hostname" {
  value       = module.argocd.service_hostname
  description = "ArgoCD LB hostname/IP"
}

output "argocd_admin_password" {
  value       = module.argocd.admin_password
  description = "ArgoCD admin password"
  sensitive   = true
}

output "grafana_service_hostname" {
  value       = module.grafana.service_hostname
  description = "Grafana LB hostname/IP"
}

output "grafana_admin_password" {
  value       = module.grafana.admin_password
  description = "Grafana admin password"
  sensitive   = true
}

output "prometheus_server_hostname" {
  value       = module.prometheus.server_service_hostname
  description = "Prometheus LB hostname/IP"
}

output "post_install_summary" {
  description = "Human-friendly summary with endpoints and how to get credentials"
  value = <<EOT
ArgoCD
- URL: ${coalesce(module.argocd.service_hostname, "<pending>") != null ? "https://" : ""}${coalesce(module.argocd.service_hostname, "<pending>")}
- Username: admin
- Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
- If no external address: kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443

Grafana
- URL: ${coalesce(module.grafana.service_hostname, "<pending>") != null ? "http://" : ""}${coalesce(module.grafana.service_hostname, "<pending>")}
- Username: admin
- Password (sensitive output): terraform output grafana_admin_password
  (or set a custom password via variable when applying)
- If no external address: kubectl -n grafana port-forward svc/grafana 3000:80
EOT
}
