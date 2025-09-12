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

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default = "demo-eks-cluster"
}