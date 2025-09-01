output "server_service_hostname" {
  description = "Prometheus server Service external hostname or IP (null for ClusterIP)"
  value       = try(data.kubernetes_service.prometheus_server.status[0].load_balancer[0].ingress[0].hostname,
                try(data.kubernetes_service.prometheus_server.status[0].load_balancer[0].ingress[0].ip, null))
}
