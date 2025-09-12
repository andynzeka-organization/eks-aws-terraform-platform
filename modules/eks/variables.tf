variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "subnet_ids" {
  description = "Subnets for the EKS cluster and node groups (typically private subnets)"
  type        = list(string)
}

variable "desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 4
}

variable "max_unavailable" {
  description = "Number of nodes that can be unavailable during a node group update"
  type        = number
  default     = 1
}

variable "force_node_group_rollout" {
  description = "Force an update of the managed node group to roll nodes when the launch template changes"
  type        = bool
  default     = true
}

variable "instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["t3.large"]
  # default     = ["t4g.small"] 
}

variable "capacity_type" {
  description = "Capacity type for node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size" {
  description = "Disk size for worker nodes in GiB"
  type        = number
#  default     = 30
}

variable "endpoint_private_access" {
  description = "Enable private access to the EKS API server endpoint"
  type        = bool
  default     = false
}

variable "endpoint_public_access" {
  description = "Enable public access to the EKS API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_log_types" {
  description = "EKS control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "tags" {
  description = "Tags to apply to EKS resources"
  type        = map(string)
  default     = {}
}

variable "node_role_additional_policy_arns" {
  description = "Additional policy ARNs to attach to the node group role"
  type        = list(string)
  default     = []
}

variable "enable_irsa_lb_controller" {
  description = "Create IRSA role for AWS Load Balancer Controller"
  type        = bool
  default     = true
}

variable "lb_controller_namespace" {
  description = "Namespace for AWS Load Balancer Controller service account"
  type        = string
  default     = "kube-system"
}

variable "lb_controller_service_account" {
  description = "Service account name for AWS Load Balancer Controller"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "lb_controller_policy_arn" {
  description = "Existing IAM policy ARN for the Load Balancer Controller (optional)"
  type        = string
  default     = null
}

variable "lb_controller_policy_json" {
  description = "JSON for creating IAM policy for the Load Balancer Controller (optional)"
  type        = string
  default     = null
}

variable "enable_irsa_ebs_csi" {
  description = "Create IRSA role for EBS CSI driver"
  type        = bool
  default     = true
}

variable "ebs_csi_namespace" {
  description = "Namespace for EBS CSI controller service account"
  type        = string
  default     = "kube-system"
}

variable "ebs_csi_service_account" {
  description = "Service account name for EBS CSI controller"
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "enable_irsa_argocd" {
  description = "Create IRSA role for ArgoCD (optional)"
  type        = bool
  default     = false
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD service account"
  type        = string
  default     = "argocd"
}

variable "argocd_service_account" {
  description = "Service account name for ArgoCD role"
  type        = string
  default     = "argocd-application-controller"
}

variable "argocd_policy_arn" {
  description = "Existing IAM policy ARN for ArgoCD (optional)"
  type        = string
  default     = null
}

variable "argocd_policy_json" {
  description = "JSON for creating IAM policy for ArgoCD (optional)"
  type        = string
  default     = null
}

variable "node_name_tag" {
  description = "Value to use for the EC2 Name tag on worker instances (optional). If null, defaults to \"<name>-node\"."
  type        = string
  default     = "demo-worker-node"
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "eks_additional_sg_ids" {
  description = "Additional security group IDs to attach to the EKS Node Group and Cluster ENIs"
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair to create"
  type        = string
  default     = "eks-node-key"
}
