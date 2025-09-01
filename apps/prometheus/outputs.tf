output "prometheus_server_hostname" {
  value       = module.prometheus.server_service_hostname
  description = "Prometheus LB hostname/IP"
}

