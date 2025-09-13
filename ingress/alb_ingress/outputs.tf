output "alb_ingress_iam_role_arn" {
  description = "ARN of the IAM role associated with the ALB Ingress controller"
  value       = aws_iam_role.alb_ingress_controller.arn
}

output "alb_ingress_service_account_name" {
  description = "Name of the service account used by the ALB ingress controller"
  value       = kubernetes_service_account.alb_sa.metadata[0].name
}

output "alb_ingress_namespace" {
  description = "Namespace where the ALB ingress controller is deployed"
  value       = kubernetes_service_account.alb_sa.metadata[0].namespace
}

output "iam_role_arn" {
  value = aws_iam_role.alb_ingress_controller.arn
} 

