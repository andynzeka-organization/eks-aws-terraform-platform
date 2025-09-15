variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region of the EKS cluster"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "namespace" {
  description = "Namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "alb_group_name" {
  description = "ALB ingress group name to join"
  type        = string
  default     = "argocd"
}

variable "tags" {
  description = "Tags to apply where supported"
  type        = map(string)
  default     = {}
}

variable "wait_for_alb_controller" {
  description = "Whether to wait for the AWS Load Balancer Controller to be ready before creating the Ingress"
  type        = bool
  default     = true
}
