# Define a null_resource to run the update-kubeconfig command
resource "null_resource" "update_kubeconfig" {
  depends_on = [aws_eks_cluster.demo-eks-cluster]
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${var.eks_cluster_name} --region ${var.region}"
  }

  # Ensure this resource runs only if it has changed
  triggers = {
    cluster_name = var.eks_cluster_name
  }
}

# Actively wait until the Kubernetes API is reachable and healthy
resource "null_resource" "wait_for_k8s_api" {
  depends_on = [
    aws_eks_cluster.demo-eks-cluster,
    null_resource.update_kubeconfig,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      echo "[wait] Checking Kubernetes API readiness"
      for i in $(seq 1 60); do
        if kubectl --request-timeout=8s get --raw=/healthz >/dev/null 2>&1; then
          echo "[wait] Kubernetes API is ready"
          exit 0
        fi
        sleep 5
      done
      echo "[wait] Timed out waiting for Kubernetes API"
      exit 1
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "null_resource" "clean_up_argocd_resources" {
  triggers = {
    eks_cluster_name = var.eks_cluster_name
    region           = var.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      kubeconfig=/tmp/tf.clean_up_argocd.kubeconfig.yaml
      aws eks update-kubeconfig --name ${self.triggers.eks_cluster_name} --region ${self.triggers.region} --kubeconfig $kubeconfig
      rm -f /tmp/tf.clean_up_argocd_resources.err.log
      kubectl --kubeconfig $kubeconfig get Application -A -o name | xargs -I {} kubectl --kubeconfig $kubeconfig -n argocd patch -p '{"metadata":{"finalizers":null}}' --type=merge {} 2> /tmp/tf.clean_up_argocd_resources.err.log || true
      rm -f $kubeconfig
    EOT
  }
}








# resource "null_resource" "clean_up_argocd_resources" {
#   triggers = {
#     eks_cluster_name = module.eks.cluster_name
#   }
#   provisioner "local-exec" {
#     command     = <<-EOT
#       kubeconfig=/tmp/tf.clean_up_argocd.kubeconfig.yaml
#       aws eks update-kubeconfig --name ${self.triggers.eks_cluster_name} --kubeconfig $kubeconfig
#       rm -f /tmp/tf.clean_up_argocd_resources.err.log
#       kubectl --kubeconfig $kubeconfig get Application -A -o name | xargs -I {} kubectl --kubeconfig $kubeconfig -n argocd patch -p '{"metadata":{"finalizers":null}}' --type=merge {} 2> /tmp/tf.clean_up_argocd_resources.err.log || true
#       rm -f $kubeconfig
#     EOT
#     interpreter = ["bash", "-c"]
#     when        = destroy
#   }
# }
