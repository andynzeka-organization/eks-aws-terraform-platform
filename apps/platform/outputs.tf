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
  description = "Grafana LB hostname/IP (null for ClusterIP)"
}

output "grafana_admin_password" {
  value       = module.grafana.admin_password
  description = "Grafana admin password"
  sensitive   = true
}

output "prometheus_server_hostname" {
  value       = module.prometheus.server_service_hostname
  description = "Prometheus LB hostname/IP (null for ClusterIP)"
}

output "monitoring_ingress_hostname" {
  description = "Ingress ALB hostname for /grafana and /prometheus"
  value       = try(kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname, null)
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
- URL: ${try(kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname, "<pending>") != "<pending>" ? "http://" : ""}${try(kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname, "<pending>")}/grafana
- Username: admin
- Password (sensitive output): terraform output grafana_admin_password
  (or set a custom password via variable when applying)
- If no external address: kubectl -n monitoring port-forward svc/grafana 3000:80
 
Prometheus
- URL: ${try(kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname, "<pending>") != "<pending>" ? "http://" : ""}${try(kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname, "<pending>")}/prometheus
EOT
}

output "grafana_ingress_url" {
  description = "Grafana URL via shared Ingress"
  value       = try("http://${kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname}/grafana", null)
}

output "prometheus_ingress_url" {
  description = "Prometheus URL via shared Ingress"
  value       = try("http://${kubernetes_ingress_v1.monitoring.status[0].load_balancer[0].ingress[0].hostname}/prometheus", null)
}

