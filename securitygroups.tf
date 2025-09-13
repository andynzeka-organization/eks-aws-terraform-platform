resource "aws_security_group" "eks_custom" {
  name        = "${var.project_name}-eks-custom"
  description = "Custom SG for EKS cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow API server -> kubelet logs/exec/portforward over 10250 within VPC
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow control plane to reach node kubelet (logs/exec)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Or adjust to your VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-custom" # 👈 This makes the name visible in the AWS console
    }
  )
  depends_on = [ module.vpc.vpc_id ]
}

# Explicitly allow kubelet access from the EKS cluster security group
resource "aws_security_group_rule" "allow_kubelet_from_cluster_sg" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_custom.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow EKS control plane (cluster SG) to reach node kubelet (10250)"
  depends_on = [ aws_security_group.eks_custom, module.eks.cluster_security_group_id ]
}

# Allow API server to reach controller webhooks on 9443 (Validating/Mutating)
resource "aws_security_group_rule" "allow_webhook_from_cluster_sg" {
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_custom.id
  source_security_group_id = module.eks.cluster_security_group_id
  description              = "Allow EKS control plane (cluster SG) to reach webhook pods (9443)"
  depends_on = [ aws_security_group.eks_custom, module.eks.cluster_security_group_id ]
}

# Also allow from the additional SG attached to both control plane ENIs and nodes.
# This covers environments where traffic originates using the additional SG instead of the cluster SG.
resource "aws_security_group_rule" "allow_webhook_from_additional_sg" {
  type                     = "ingress"
  from_port                = 9443
  to_port                  = 9443
  protocol                 = "tcp"
 security_group_id        = aws_security_group.eks_custom.id
  source_security_group_id = aws_security_group.eks_custom.id
  description              = "Allow control plane/node additional SG to reach webhook pods (9443)"
  depends_on = [ aws_security_group.eks_custom ]
}

# # From EKS NodeGroup SG to Pod SG
# resource "aws_security_group_rule" "allow_webhook_from_node_sg" {
#   type                     = "ingress"
#   from_port                = 9443
#   to_port                  = 9443
#   protocol                 = "tcp"
#   security_group_id        = aws_security_group.eks_custom.id
#   source_security_group_id = module.eks.node_security_group_id # or wherever this is output from
#   description              = "Allow EKS node SG to reach webhook pods"
# }
