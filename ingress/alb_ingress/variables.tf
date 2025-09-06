variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "demo-eks-cluster"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC Provider for EKS"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL of the EKS cluster"
  type        = string
  # Optional: not used by this module anymore
  default     = null
}

variable "vpc_id" {
  description = "ID of the VPC where the ALB Ingress Controller will operate"
  type        = string
}

variable "alb_ingress_sa_name" {
  description = "Name of the Kubernetes service account for ALB ingress controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "alb_ingress_namespace" {
  description = "Namespace where the ALB ingress controller will be installed"
  type        = string
  default     = "kube-system"
}

variable "tags" {
  description = "Tags to apply to EKS resources"
  type        = map(string)
  default     = {}
}
