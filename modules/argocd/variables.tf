variable "namespace" {
  description = "Namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "create_namespace" {
  description = "Create the namespace if it does not exist"
  type        = bool
  default     = true
}

variable "service_type" {
  description = "Kubernetes Service type for argocd-server (ClusterIP or LoadBalancer)"
  type        = string
  default     = "LoadBalancer"
}

variable "service_annotations" {
  description = "Additional annotations for the argocd-server Service"
  type        = map(string)
  default     = {
    "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type"  = "ip"
  }
}

