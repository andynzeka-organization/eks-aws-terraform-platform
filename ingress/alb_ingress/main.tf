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

# Use a single source policy file and split it at apply time to
# satisfy the 6KB IAM policy size limit.
locals {
  alb_policy_src = jsondecode(file("${path.module}/alb-ingress-controller-policy.json"))

  # 1) Normalize: ensure Action is a list and de-duplicate actions per statement
  alb_policy_statements_norm = [
    for st in local.alb_policy_src.Statement :
    can(st.Action[0])
    ? merge(st, { Action = distinct(st.Action) })
    : (
        st.Action != null
        ? merge(st, { Action = [st.Action] })
        : st
      )
  ]

  # 2) Augment: add missing Describe* that controller relies on
  alb_policy_statements_augmented_1 = [
    for st in local.alb_policy_statements_norm :
    (contains(st.Action, "elasticloadbalancing:DescribeListeners") && !contains(st.Action, "elasticloadbalancing:DescribeListenerAttributes"))
    ? merge(st, { Action = concat(st.Action, ["elasticloadbalancing:DescribeListenerAttributes"]) })
    : st
  ]

  # Include DescribeTrustStores if the broad describe block is present
  alb_policy_statements_augmented_2 = [
    for st in local.alb_policy_statements_augmented_1 :
    (contains(st.Action, "elasticloadbalancing:DescribeLoadBalancers") && !contains(st.Action, "elasticloadbalancing:DescribeTrustStores"))
    ? merge(st, { Action = concat(st.Action, ["elasticloadbalancing:DescribeTrustStores"]) })
    : st
  ]

  # 3) De-duplicate identical statements
  alb_policy_statements_dedup = [
    for s in distinct([for st in local.alb_policy_statements_augmented_2 : jsonencode(st)]) : jsondecode(s)
  ]

  alb_policy_part1_json = jsonencode({
    Version   = local.alb_policy_src.Version
    Statement = slice(local.alb_policy_statements_dedup, 0, 11)
  })

  alb_policy_part2_json = jsonencode({
    Version   = local.alb_policy_src.Version
    Statement = slice(local.alb_policy_statements_dedup, 11, length(local.alb_policy_statements_dedup))
  })
}

resource "aws_iam_policy" "alb_ingress_controller_part1" {
  name        = "AWSLoadBalancerControllerIAMPolicy-Part1"
  path        = "/"
  description = "Policy for ALB Ingress Controller (part 1)"

  policy = local.alb_policy_part1_json
}

resource "aws_iam_policy" "alb_ingress_controller_part2" {
  name        = "AWSLoadBalancerControllerIAMPolicy-Part2"
  path        = "/"
  description = "Policy for ALB Ingress Controller (part 2)"

  policy = local.alb_policy_part2_json
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


###########################################
# 4. Install AWS LB Controller via Helm   #
###########################################
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = var.alb_ingress_namespace
  # Pin to chart compatible with controller v2.13.x
  version    = "1.13.4"

  # Ensure CRDs and SA exist first
  depends_on = [
    kubernetes_service_account.alb_sa,
    aws_iam_role_policy_attachment.alb_ingress_policy_attach,
    aws_iam_role_policy_attachment.alb_ingress_policy_attach_part2,
  ]

  values = [yamlencode({
    clusterName        = var.eks_cluster_name
    region             = var.aws_region
    vpcId              = var.vpc_id
    serviceAccount = {
      create = false
      name   = var.alb_ingress_sa_name
    }
    rbac = {
      create = true
    }
    createIngressClass = true
    ingressClass       = "alb"
    logLevel           = "info"
  })]
}



# Note: We use a single source file `alb-ingress-controller-policy.json` and
# split it into two customer-managed policies at apply time to stay under
# the IAM policy size limit.

#### Copy Paste ####

# helm repo add eks https://aws.github.io/eks-charts
# helm repo update

# helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller --set vpcId=vpc-07b46a112f1f5aaa0  --set clusterName=demo-eks-cluster --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --set region=us-east-1 --namespace kube-system 

# kubectl get deployment -n  kube-system aws-load-balancer-controller
# kubectl get pod -n kube-system
# kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller 
