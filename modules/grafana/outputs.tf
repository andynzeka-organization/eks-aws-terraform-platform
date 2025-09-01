output "service_hostname" {
  description = "Grafana Service external hostname or IP (null for ClusterIP)"
  value       = try(data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname,
                try(data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip, null))
}

output "admin_password" {
  description = "Grafana admin password"
  value       = var.admin_password
  sensitive   = true
}
