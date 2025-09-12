variable "project_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = []
}

variable "enable_nat_per_az" {
  description = "Create NAT gateway per AZ"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "demo-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (e.g., 1.31). Leave null to use the latest at creation time."
  type        = string
  default     = "1.33"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "enable_argocd_irsa" {
  description = "Enable IRSA role for ArgoCD"
  type        = bool
  default     = false
}

variable "enable_monitoring_stack" {
  description = "Install kube-prometheus-stack"
  type        = bool
  default     = false
}

variable "helm_namespace_argocd" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "helm_namespace_monitoring" {
  description = "Namespace for Monitoring stack"
  type        = string
  default     = "monitoring"
}

variable "disk_size" {
  description = "Disk size for worker nodes in GiB"
  type        = number
  default     = 35
}

# variable "eks_cluster_name" {
#   type        = string
#   description = "Name of the EKS Cluster"
# }