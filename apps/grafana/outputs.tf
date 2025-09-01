output "grafana_service_hostname" {
  value       = module.grafana.service_hostname
  description = "Grafana LB hostname/IP"
}

output "grafana_admin_password" {
  value       = module.grafana.admin_password
  description = "Grafana admin password"
  sensitive   = true
}

