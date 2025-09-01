variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "irsa_role_arn" {
  description = "IAM Role ARN for the ALB controller service account"
  type        = string
}

