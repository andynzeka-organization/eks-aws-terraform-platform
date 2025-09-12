output "service_hostname" {
  description = "Grafana Service external hostname or IP (null for ClusterIP)"
  value       = try(
    coalesce(
      try(data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].hostname, null),
      try(data.kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip, null)
    ),
    null
  )
}

output "admin_password" {
  description = "Grafana admin password"
  value       = coalesce(var.admin_password, try(random_password.grafana_admin[0].result, null))
  sensitive   = true
}
