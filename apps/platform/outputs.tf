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

