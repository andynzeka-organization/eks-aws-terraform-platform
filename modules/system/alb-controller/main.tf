resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  wait       = true
  timeout    = 900
  atomic     = true

  values = [yamlencode({
    clusterName    = var.cluster_name
    region         = var.region
    vpcId          = var.vpc_id
    serviceAccount = {
      create      = true
      name        = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.irsa_role_arn
      }
    }
  })]
}

