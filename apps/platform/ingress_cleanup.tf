# -------------------------------------------------------------------------
# ingress_cleanup.tf
# Automated cleanup of Ingresses, ALBs, Target Groups, and Security Groups
# Ensures Terraform destroy does not hang due to finalizers, orphaned ALBs, or SGs
# -------------------------------------------------------------------------

# -------------------------------
# 1. Define ingresses to clean
# -------------------------------
# List of Kubernetes ingresses that require finalizer removal before destruction
locals {
  ingresses_to_clean = [
    kubernetes_ingress_v1.argocd,
    # kubernetes_ingress_v1.grafana, # disabled
  ]
}

# -------------------------------
# 2. Remove finalizers from Ingresses
# -------------------------------
# Using null_resource with for_each to iterate over ingresses
# Removes finalizers using kubectl patch to allow deletion
resource "null_resource" "remove_ingress_finalizers" {
  for_each = var.enable_ingress_cleanup ? { for i, ing in local.ingresses_to_clean : ing.metadata[0].name => ing } : {}

  provisioner "local-exec" {
    command = <<EOT
echo "Removing finalizers for ingress ${each.value.metadata[0].name} in namespace ${each.value.metadata[0].namespace}..."
kubectl patch ingress ${each.value.metadata[0].name} -n ${each.value.metadata[0].namespace} -p '{"metadata":{"finalizers":null}}' --type=merge || true
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    kubernetes_ingress_v1.argocd
  ]
}

# -------------------------------
# 3. Wait for ALB deletion
# -------------------------------
# ALBs created by Kubernetes may still exist; wait until they are fully deleted
resource "null_resource" "wait_for_alb_deletion" {
  count = var.enable_ingress_cleanup ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
echo "Fetching ALBs for cluster ${var.eks_cluster_name}..."
alb_arns=$(aws elbv2 describe-load-balancers --region ${var.aws_region} \
  --query "LoadBalancers[?contains(Tags[?Key=='kubernetes.io/cluster/${var.eks_cluster_name}'].Value | [0], 'owned')].LoadBalancerArn" \
  --output text)

for alb in $alb_arns; do
  echo "Waiting for ALB $alb to be deleted..."
  while aws elbv2 describe-load-balancers --load-balancer-arns $alb --region ${var.aws_region} >/dev/null 2>&1; do
    sleep 10
  done
  echo "ALB $alb deleted."
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    null_resource.remove_ingress_finalizers
  ]
}

# -------------------------------
# 4. Delete orphaned target groups
# -------------------------------
# Find target groups that have no attached ALB and delete them
resource "null_resource" "delete_orphaned_target_groups" {
  count = var.enable_ingress_cleanup ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
echo "Fetching orphaned target groups..."
aws elbv2 describe-target-groups --region ${var.aws_region} \
  --query 'TargetGroups[?length(LoadBalancerArns)==`0`].[TargetGroupArn]' --output text | while read tg_arn; do
    [ -z "$tg_arn" ] && continue
    echo "Deleting orphaned target group: $tg_arn"
    aws elbv2 delete-target-group --target-group-arn $tg_arn || true
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    null_resource.wait_for_alb_deletion
  ]
}

# -------------------------------
# 5. Delete all ALB-created security groups in the VPC
# -------------------------------
# These SGs are typically attached to ALBs and must be deleted before VPC
data "aws_vpc" "platform_vpc" {
  id = data.terraform_remote_state.infra.outputs.vpc_id
}

resource "null_resource" "delete_k8s_alb_sgs" {
  provisioner "local-exec" {
    command = <<EOT
echo "Fetching ALB-related security groups in VPC ${data.aws_vpc.platform_vpc.id}..."
aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values=${data.aws_vpc.platform_vpc.id} \
            Name=tag:elbv2.k8s.aws/cluster,Values=${var.eks_cluster_name} \
  --query 'SecurityGroups[].GroupId' --output text | while read sg; do
    [ -z "$sg" ] && continue
    echo "Deleting ALB SG: $sg"
    aws ec2 delete-security-group --group-id $sg || true
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    null_resource.delete_orphaned_target_groups
  ]
}

# -------------------------------
# 6. Optional: Wait and double-check ALB SG deletion
# -------------------------------
# Ensures all security groups associated with ALBs are deleted
# before allowing Terraform to destroy the VPC
resource "null_resource" "wait_and_delete_alb_sgs" {
  count = var.enable_ingress_cleanup ? 1 : 0
  provisioner "local-exec" {
    command = <<EOT
echo "Final cleanup: waiting for any remaining ALBs..."
alb_arns=$(aws elbv2 describe-load-balancers --region ${var.aws_region} \
  --query "LoadBalancers[?contains(Tags[?Key=='kubernetes.io/cluster/${var.eks_cluster_name}'].Value, 'owned')].LoadBalancerArn" \
  --output text)

for alb in $alb_arns; do
  while aws elbv2 describe-load-balancers --load-balancer-arns $alb --region ${var.aws_region} >/dev/null 2>&1; do
    sleep 10
  done
done

echo "Deleting any remaining cluster SGs..."
sgs=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text) Name=tag:elbv2.k8s.aws/cluster,Values=${var.eks_cluster_name} \
  --query 'SecurityGroups[].GroupId' --output text)

for sg in $sgs; do
  [ -z "$sg" ] && continue
  echo "Deleting SG: $sg"
  aws ec2 delete-security-group --group-id $sg || true
done
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }
}


# -------------------------------------------------------------------------
# Explicitly remove finalizers for argocd and grafana ingress
# -------------------------------------------------------------------------
resource "null_resource" "force_remove_ingress_finalizers" {
  provisioner "local-exec" {
    command = <<EOT
echo "Removing finalizers for argocd ingress..."
kubectl patch ingress argocd -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge || true

echo "Grafana ingress disabled; skipping finalizer removal."
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [
    kubernetes_ingress_v1.argocd,
    # kubernetes_ingress_v1.grafana
  ]
}

# # -------------------------------------------------------------------------
# # Destroy-time cleanup: remove Ingress finalizers, delete ALBs/TGs/ALB SGs
# # This runs during terraform destroy of the apps/platform stack to unblock VPC destroy
# # -------------------------------------------------------------------------
# resource "null_resource" "cleanup_on_destroy" {
#   provisioner "local-exec" {
#     when        = destroy
#     interpreter = ["/bin/bash", "-c"]
#     command     = <<EOT
# set -euo pipefail
# echo "[cleanup-destroy] Stripping finalizers on Ingresses (argocd, grafana) if present..."
# kubectl patch ingress argocd -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true
# kubectl patch ingress grafana -n monitoring -p '{"metadata":{"finalizers":null}}' --type=merge >/dev/null 2>&1 || true

# echo "[cleanup-destroy] Deleting Ingresses if they still exist..."
# kubectl delete ingress argocd -n argocd --ignore-not-found >/dev/null 2>&1 || true
# kubectl delete ingress grafana -n monitoring --ignore-not-found >/dev/null 2>&1 || true

# echo "[cleanup-destroy] Deleting TargetGroupBindings to allow ALB controller to cleanup..."
# kubectl delete targetgroupbindings.elbv2.k8s.aws --all -A --ignore-not-found >/dev/null 2>&1 || true

# echo "[cleanup-destroy] Resolving region, cluster and VPC..."
# REGION="$AWS_REGION"
# [ -z "$REGION" ] && REGION="$AWS_DEFAULT_REGION"
# [ -z "$REGION" ] && REGION="us-east-1"
# CLUSTER="$CLUSTER_NAME"
# [ -z "$CLUSTER" ] && CLUSTER="demo-eks-cluster"
# VPC_ID=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null || echo "")
# echo "  - REGION=$${REGION} CLUSTER=$${CLUSTER} VPC_ID=$${VPC_ID:-<unknown>}"

# # Tuning knobs for cleanup behavior
# TIMEOUT=$${CLEANUP_TIMEOUT:-900}
# SLEEP=$${CLEANUP_SLEEP:-10}
# FAST=$${FAST_ELB_CLEAN:-false}

# if [[ "$FAST" == "true" ]]; then
#   echo "[cleanup-destroy] FAST_ELB_CLEAN=true -> deleting ALBs/TargetGroups by cluster tag..."
#   # Delete Load Balancers tagged to this cluster
#   for alb in $(aws elbv2 describe-load-balancers --region "$REGION" \
#       --query "LoadBalancers[?contains(Tags[?Key=='kubernetes.io/cluster/$${CLUSTER}'].Value | [0], 'owned')].LoadBalancerArn" \
#       --output text 2>/dev/null || true); do
#     [ -z "$alb" ] && continue
#     echo "  - deleting LB: $alb"
#     aws elbv2 delete-load-balancer --load-balancer-arn "$alb" --region "$REGION" >/dev/null 2>&1 || true
#   done
#   # Delete Target Groups tagged to this cluster
#   for tg in $(aws elbv2 describe-target-groups --region "$REGION" \
#       --query "TargetGroups[?contains(Tags[?Key=='kubernetes.io/cluster/$${CLUSTER}'].Value | [0], 'owned')].TargetGroupArn" \
#       --output text 2>/dev/null || true); do
#     [ -z "$tg" ] && continue
#     echo "  - deleting TG: $tg"
#     aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" >/dev/null 2>&1 || true
#   done
# fi

# echo "[cleanup-destroy] Waiting for ALBs with cluster tag to disappear..."
# START=$(date +%s)
# while true; do
#   count=$(aws elbv2 describe-load-balancers --region "$REGION" \
#     --query "length(LoadBalancers[?contains(Tags[?Key=='kubernetes.io/cluster/$${CLUSTER}'].Value | [0], 'owned')])" 2>/dev/null || echo 0)
#   echo "  - remaining ALBs tagged to cluster: $${count:-0}"
#   if [[ "$${count:-0}" -eq 0 ]]; then
#     break
#   fi
#   now=$(date +%s)
#   if (( now - START > TIMEOUT )); then
#     echo "[cleanup-destroy] Timeout waiting for ALB deletion; proceeding." >&2
#     break
#   fi
#   sleep "$SLEEP"
# done

# echo "[cleanup-destroy] Deleting orphaned Target Groups in region $REGION..."
# aws elbv2 describe-target-groups --region "$REGION" --query 'TargetGroups[?length(LoadBalancerArns)==`0`].[TargetGroupArn]' --output text 2>/dev/null | while read tg; do
#   [ -z "$tg" ] && continue
#   echo "  - deleting TG $tg"
#   aws elbv2 delete-target-group --target-group-arn "$tg" --region "$REGION" >/dev/null 2>&1 || true
# done

# if [ -n "$VPC_ID" ]; then
#   echo "[cleanup-destroy] Deleting ALB-created Security Groups in VPC $VPC_ID..."
#   aws ec2 describe-security-groups --region "$REGION" \
#     --filters Name=vpc-id,Values=$VPC_ID \
#              Name=tag:elbv2.k8s.aws/cluster,Values="$CLUSTER" \
#     --query 'SecurityGroups[].GroupId' --output text 2>/dev/null | while read sg; do
#     [ -z "$sg" ] && continue
#     echo "  - deleting SG $sg"
#     aws ec2 delete-security-group --group-id "$sg" --region "$REGION" >/dev/null 2>&1 || true
#   done
# else
#   echo "[cleanup-destroy] Skipping ALB SG deletion: could not resolve VPC ID."
# fi

# echo "[cleanup-destroy] Cleanup complete."
# EOT
#   }
# }
