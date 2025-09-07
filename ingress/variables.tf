variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (override or fallback when remote state isn't available)"
  type        = string
  default     = "demo-eks-cluster"
}

variable "oidc_provider_arn_override" {
  description = "Optional override for the EKS cluster's OIDC provider ARN (use when remote state is unavailable)"
  type        = string
  default     = null
}

variable "vpc_id_override" {
  description = "Optional override for the VPC ID to use (bypass remote state)"
  type        = string
  default     = null
}
