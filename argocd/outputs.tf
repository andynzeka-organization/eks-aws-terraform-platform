output "argocd_ingress_hostname" {
  description = "Ingress hostname for ArgoCD"
  value       = try(kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "argocd_url" {
  description = "ArgoCD URL"
  value       = try("http://" + kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname + "/argocd", null)
}

