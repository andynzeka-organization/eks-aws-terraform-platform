module "alb_ingress" {
  source            = "./alb_ingress"
  eks_cluster_name  = local.cluster_name
  # Prefer explicit override; fall back to remote state
  oidc_provider_arn = coalesce(
    var.oidc_provider_arn_override,
    local.oidc_provider_arn_auto,
    try(data.terraform_remote_state.infra.outputs.cluster_oidc_provider_arn, null)
  )
  aws_region        = var.aws_region
  vpc_id            = coalesce(
    var.vpc_id_override,
    local.vpc_id_auto,
    try(data.terraform_remote_state.infra.outputs.vpc_id, null)
  )
}

