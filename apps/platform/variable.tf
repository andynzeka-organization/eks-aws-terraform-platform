variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"

}

variable "alb_webhook_timeout" {
  description = "Seconds to wait for ALB controller webhook endpoints to be ready"
  type        = number
  default     = 1800
}

variable "enable_ingress_preflight" {
  description = "Enable preflight that validates annotated subnets belong to the controller VPC and are properly tagged"
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default = "demo-eks-cluster"
}

variable "enable_ingress_cleanup" {
  description = "Enable ALB/TargetGroup cleanup helpers during platform apply"
  type        = bool
  default     = false
}
