resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  wait       = true
  timeout    = 900

  values = [yamlencode({
    controller = {
      serviceAccount = {
        create      = true
        name        = "ebs-csi-controller-sa"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.irsa_role_arn
        }
      }
    }
  })]
}

