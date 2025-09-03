locals {
  base_tags = merge({
    "Name" = var.eks_cluster_name
  }, var.tags)
  node_name_tag = coalesce(var.node_name_tag, "${var.eks_cluster_name}-node")
}

# data "aws_ami" "eks_worker" {
#   most_recent = true
#   filter {
#     name   = "name"
#     values = ["amazon-eks-node-*-x86_64-*"]
#   }
#   filter {
#     name   = "owner-id"
#     values = ["602401143452"] # Amazon EKS AMI owner
#   }
#   filter {
#     name   = "architecture"
#     values = ["x86_64"]
#   }
#   owners = ["602401143452"]
# }


// IAM Role for EKS Control Plane
data "aws_iam_policy" "AmazonEKSClusterPolicy" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy" "AmazonEKSVPCResourceController" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "cluster" {
  name               = "${var.eks_cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = merge(local.base_tags, { Component = "eks-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = data.aws_iam_policy.AmazonEKSClusterPolicy.arn
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.cluster.name
  policy_arn = data.aws_iam_policy.AmazonEKSVPCResourceController.arn
}

// IAM Role for Nodes
data "aws_iam_policy" "AmazonEKSWorkerNodePolicy" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

data "aws_iam_policy" "AmazonEKS_CNI_Policy" {
  arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_policy" "AmazonEC2ContainerRegistryReadOnly" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role" "node" {
  name               = "${var.eks_cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.base_tags, { Component = "eks-node-role" })
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.AmazonEKSWorkerNodePolicy.arn
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.AmazonEKS_CNI_Policy.arn
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.AmazonEC2ContainerRegistryReadOnly.arn
}

resource "aws_iam_role_policy_attachment" "node_additional" {
  for_each   = toset(var.node_role_additional_policy_arns)
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

// EKS Cluster
resource "aws_eks_cluster" "demo-eks-cluster" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    security_group_ids = var.eks_additional_sg_ids
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = merge(local.base_tags, { Component = "eks-cluster" })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController
  ]
}

// OIDC provider for IRSA
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.demo-eks-cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "openid" {
  url = aws_eks_cluster.demo-eks-cluster.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    data.tls_certificate.oidc.certificates[0].sha1_fingerprint
  ]
}

// Launch template to apply Name tag to instances in the node group
resource "aws_launch_template" "node" {
  name_prefix = "${var.eks_cluster_name}-ng"
  vpc_security_group_ids = var.eks_additional_sg_ids
  key_name      = var.ssh_key_name
  
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size           # e.g., 20
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.base_tags, {
      Name = local.node_name_tag
    })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = local.base_tags
  }
  tags = merge(local.base_tags, { Component = "eks-node-lt" })
}

# 1. Generate a new SSH key pair locally
resource "tls_private_key" "eks_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# 2. Upload the public key to AWS as a named key pair
resource "aws_key_pair" "eks_key_pair" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.eks_key.public_key_openssh
}

# 3. Save the private key to your local machine (be careful with permissions)
resource "local_file" "private_key_pem" {
  content              = tls_private_key.eks_key.private_key_pem
  filename             = "${path.module}/keys/${var.ssh_key_name}.pem"
  file_permission      = "0600"
  directory_permission = "0700"
}


// Node Group
resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.demo-eks-cluster.name
  node_group_name = "${var.eks_cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }
  update_config {
    max_unavailable = var.max_unavailable
  }
  force_update_version = var.force_node_group_rollout
  capacity_type  = var.capacity_type
  instance_types = var.instance_types
  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }
  tags = merge(local.base_tags, { Component = "eks-node-group" })
  depends_on = [
    aws_eks_cluster.demo-eks-cluster,
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,]
}

// Helper to build IRSA trust policy
locals {
  oidc_provider_arn = aws_iam_openid_connect_provider.openid.arn
  oidc_provider_url = replace(aws_iam_openid_connect_provider.openid.url, "https://", "")
}

// AWS Load Balancer Controller IRSA
resource "aws_iam_role" "lb_controller" {
  count = var.enable_irsa_lb_controller ? 1 : 0
  name  = "${var.eks_cluster_name}-irsa-alb"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.lb_controller_namespace}:${var.lb_controller_service_account}"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = merge(local.base_tags, { Component = "irsa-alb" })
}

resource "aws_iam_policy" "lb_controller_inline" {
  count       = var.enable_irsa_lb_controller && var.lb_controller_policy_json != null ? 1 : 0
  name        = "${var.eks_cluster_name}-alb-controller-policy"
  description = "Policy for AWS Load Balancer Controller"
  policy      = var.lb_controller_policy_json
}

resource "aws_iam_role_policy_attachment" "lb_controller_attach_custom" {
  count      = var.enable_irsa_lb_controller && var.lb_controller_policy_json != null ? 1 : 0
  role       = aws_iam_role.lb_controller[0].name
  policy_arn = aws_iam_policy.lb_controller_inline[0].arn
}

resource "aws_iam_role_policy_attachment" "lb_controller_attach_existing" {
  count      = var.enable_irsa_lb_controller && var.lb_controller_policy_json == null && var.lb_controller_policy_arn != null ? 1 : 0
  role       = aws_iam_role.lb_controller[0].name
  policy_arn = var.lb_controller_policy_arn
}

// EBS CSI IRSA
resource "aws_iam_role" "ebs_csi" {
  count = var.enable_irsa_ebs_csi ? 1 : 0
  name  = "${var.eks_cluster_name}-irsa-ebs-csi"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.ebs_csi_namespace}:${var.ebs_csi_service_account}"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = merge(local.base_tags, { Component = "irsa-ebs-csi" })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_attach" {
  count      = var.enable_irsa_ebs_csi ? 1 : 0
  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

// ArgoCD IRSA (optional)
resource "aws_iam_role" "argocd" {
  count = var.enable_irsa_argocd ? 1 : 0
  name  = "${var.eks_cluster_name}-irsa-argocd"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:${var.argocd_namespace}:${var.argocd_service_account}"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = merge(local.base_tags, { Component = "irsa-argocd" })
}

resource "aws_iam_policy" "argocd_inline" {
  count       = var.enable_irsa_argocd && var.argocd_policy_json != null ? 1 : 0
  name        = "${var.eks_cluster_name}-argocd-policy"
  description = "Policy for ArgoCD (custom)"
  policy      = var.argocd_policy_json
}

resource "aws_iam_role_policy_attachment" "argocd_attach_custom" {
  count      = var.enable_irsa_argocd && var.argocd_policy_json != null ? 1 : 0
  role       = aws_iam_role.argocd[0].name
  policy_arn = aws_iam_policy.argocd_inline[0].arn
}

resource "aws_iam_role_policy_attachment" "argocd_attach_existing" {
  count      = var.enable_irsa_argocd && var.argocd_policy_json == null && var.argocd_policy_arn != null ? 1 : 0
  role       = aws_iam_role.argocd[0].name
  policy_arn = var.argocd_policy_arn
}
