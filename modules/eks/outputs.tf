output "cluster_name" {
  value       = aws_eks_cluster.demo-eks-cluster.name
  description = "EKS cluster name"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.demo-eks-cluster.endpoint
  description = "EKS cluster API server endpoint"
}

output "cluster_ca" {
  value       = aws_eks_cluster.demo-eks-cluster.certificate_authority[0].data
  description = "EKS cluster certificate authority data"
}

output "cluster_oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.openid.arn
  description = "OIDC provider ARN for IRSA"
}

output "node_group_name" {
  value       = aws_eks_node_group.worker-node.node_group_name
  description = "Default node group name"
}

output "node_role_arn" {
  value       = aws_iam_role.node.arn
  description = "Node group IAM role ARN"
}

output "irsa_lb_controller_role_arn" {
  value       = try(aws_iam_role.lb_controller[0].arn, null)
  description = "IRSA role ARN for AWS Load Balancer Controller (if created)"
}

output "irsa_ebs_csi_role_arn" {
  value       = try(aws_iam_role.ebs_csi[0].arn, null)
  description = "IRSA role ARN for EBS CSI driver (if created)"
}

output "irsa_argocd_role_arn" {
  value       = try(aws_iam_role.argocd[0].arn, null)
  description = "IRSA role ARN for ArgoCD (if created)"
}
