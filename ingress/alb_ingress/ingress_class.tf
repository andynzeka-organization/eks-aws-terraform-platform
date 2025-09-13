resource "kubernetes_ingress_class_v1" "alb" {
  metadata {
    name = "alb"
    # Add Helm ownership metadata so Helm can adopt this resource if it renders it
    labels = {
      "app.kubernetes.io/managed-by" = "Helm"
    }
    annotations = {
      "meta.helm.sh/release-name"      = "aws-load-balancer-controller"
      "meta.helm.sh/release-namespace" = var.alb_ingress_namespace
    }
  }
  spec {
    controller = "ingress.k8s.aws/alb"
  }
}
