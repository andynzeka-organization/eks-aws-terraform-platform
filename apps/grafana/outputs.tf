output "grafana_service_hostname" {
  value       = module.grafana.service_hostname
  description = "Grafana LB hostname/IP"
}

output "grafana_admin_password" {
  value       = module.grafana.admin_password
  description = "Grafana admin password"
  sensitive   = true
}

output "post_install_summary" {
  description = "Human-friendly summary for Grafana access"
  value = <<EOT
Grafana
- URL: ${coalesce(module.grafana.service_hostname, "<pending>") != null ? "http://" : ""}${coalesce(module.grafana.service_hostname, "<pending>")}
- Username: admin
- Password (sensitive output): terraform output grafana_admin_password
- If no external address: kubectl -n monitoring port-forward svc/grafana 3000:80
EOT
}
