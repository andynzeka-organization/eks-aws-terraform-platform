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

# Shared ALB DNS (from grafana or argocd ingress)
locals {
  shared_alb_candidates = [
    try(kubernetes_ingress_v1.grafana.status[0].load_balancer[0].ingress[0].hostname, null),
    try(kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, null)
  ]
  shared_alb_dns = try(compact(local.shared_alb_candidates)[0], null)
}

output "shared_alb_dns" {
  description = "Shared ALB DNS used by platform ingresses"
  value       = local.shared_alb_dns
}

output "post_install_summary" {
  description = "Human-friendly summary with endpoints and how to get credentials"
  value       = <<EOT
ArgoCD
- URL: ${local.shared_alb_dns != null ? "http://" : ""}${coalesce(local.shared_alb_dns, "<pending>")}/argocd
- Username: admin
- Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
- If no external address: kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
 
Grafana
- URL: ${local.shared_alb_dns != null ? "http://" : ""}${coalesce(local.shared_alb_dns, "<pending>")}/grafana
- Username: admin
- Password (sensitive output): terraform output grafana_admin_password
- If no external address: kubectl -n monitoring port-forward svc/grafana 3000:80
EOT
}

output "grafana_ingress_url" {
  description = "Grafana URL via shared Ingress"
  value       = try("http://${local.shared_alb_dns}/grafana", null)
}

output "argocd_ingress_url" {
  description = "Argo CD URL via shared Ingress"
  value       = try("http://${local.shared_alb_dns}/argocd", null)
}

output "platform_urls" {
  description = "Combined URLs for ArgoCD and Grafana with readiness hint"
  value = {
    alb_dns = local.shared_alb_dns
    status  = local.shared_alb_dns != null ? "ready" : "pending"
    argocd  = local.shared_alb_dns != null ? "http://${local.shared_alb_dns}/argocd"  : "<ALB pending>"
    grafana = local.shared_alb_dns != null ? "http://${local.shared_alb_dns}/grafana" : "<ALB pending>"
    note    = local.shared_alb_dns != null ? "" : "ALB DNS pending; wait a few minutes or annotate Ingress with explicit public subnets to force reconciliation."
  }
}
