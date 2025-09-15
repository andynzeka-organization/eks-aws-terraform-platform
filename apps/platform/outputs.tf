output "argocd_server_hostname" {
  value       = module.argocd.service_hostname
  description = "ArgoCD LB hostname/IP"
}

output "argocd_admin_password" {
  value       = module.argocd.admin_password
  description = "ArgoCD admin password"
  sensitive   = true
}

/*
output "grafana_service_hostname" {
  value       = module.grafana.service_hostname
  description = "Grafana LB hostname/IP (null for ClusterIP)"
}

output "grafana_admin_password" {
  value       = module.grafana.admin_password
  description = "Grafana admin password"
  sensitive   = true
}
*/

# Shared ALB DNS (from grafana or argocd ingress)
locals {
  shared_alb_candidates = [
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
 
/* Grafana disabled */
EOT
}

/*
output "grafana_ingress_url" {
  description = "Grafana URL via shared Ingress"
  value       = try("http://${local.shared_alb_dns}/grafana", null)
}
*/

/*
output "grafana_password_command" {
  description = "Command to retrieve the Grafana admin password from the Kubernetes secret"
  value       = "kubectl -n monitoring get secret grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
}
*/

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
    note    = local.shared_alb_dns != null ? "" : "ALB DNS pending; wait a few minutes or annotate Ingress with explicit public subnets to force reconciliation."
  }
}

output "kubernetes_ingress_argocd" {
  value = kubernetes_ingress_v1.argocd
}

/*
output "kubernetes_ingress_grafana" {
  value = kubernetes_ingress_v1.grafana
}
*/

# platform/outputs.tf
output "argocd_ingress_name" {
  value = kubernetes_ingress_v1.argocd.metadata[0].name
}

/*
output "grafana_ingress_name" {
  value = kubernetes_ingress_v1.grafana.metadata[0].name
}
*/
output "argocd_ingress_namespace" {
  value = kubernetes_ingress_v1.argocd.metadata[0].namespace
}

/*
output "grafana_ingress_namespace" {
  value = kubernetes_ingress_v1.grafana.metadata[0].namespace
}
*/
