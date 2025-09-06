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
