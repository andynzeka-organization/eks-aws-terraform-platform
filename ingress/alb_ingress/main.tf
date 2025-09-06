############################
# 1. Enable OIDC Provider #
############################
data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.eks_cluster_name
}

###################################
# 2. Create IAM Role + Attach Policies #
###################################
resource "aws_iam_policy" "alb_ingress_controller_part1" {
  name        = "AWSLoadBalancerControllerIAMPolicy-Part1"
  path        = "/"
  description = "Policy for ALB Ingress Controller (part 1)"

  # Compact first half of the official policy
  policy = file("${path.module}/alb-ingress-controller-policy.part1.min.json")
}

resource "aws_iam_policy" "alb_ingress_controller_part2" {
  name        = "AWSLoadBalancerControllerIAMPolicy-Part2"
  path        = "/"
  description = "Policy for ALB Ingress Controller (part 2)"

  # Compact second half of the official policy
  policy = file("${path.module}/alb-ingress-controller-policy.part2.min.json")
}

resource "aws_iam_role" "alb_ingress_controller" {
  name = "AmazonEKSLoadBalancerControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.alb_ingress_namespace}:${var.alb_ingress_sa_name}"
            "${replace(data.aws_eks_cluster.eks.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_ingress_policy_attach" {
  role       = aws_iam_role.alb_ingress_controller.name
  policy_arn = aws_iam_policy.alb_ingress_controller_part1.arn
}

resource "aws_iam_role_policy_attachment" "alb_ingress_policy_attach_part2" {
  role       = aws_iam_role.alb_ingress_controller.name
  policy_arn = aws_iam_policy.alb_ingress_controller_part2.arn
}

#########################################################
# 3. Create Service Account linked to the IAM Role (IRSA)
#########################################################
resource "kubernetes_service_account" "alb_sa" {
  metadata {
    name      = var.alb_ingress_sa_name
    namespace = var.alb_ingress_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_ingress_controller.arn
    }
  }
}



# Note: We now use the AWS-managed policy `AWSLoadBalancerControllerIAMPolicy`.
# The local `alb-ingress-controller-policy.json` file is retained for reference
# but is not used to create a customer-managed policy.

#### Copy Paste ####

# helm repo add eks https://aws.github.io/eks-charts
# helm repo update

# helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller  --set clusterName=demo-eks-cluster --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=us-east-1 --set vpcId=vpc-04fd9fc1b14c2e0cd --namespace kube-system 

# kubectl get deployment -n  kube-system aws-load-balancer-controller
# kubectl get pod -n kube-system
# kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller 




