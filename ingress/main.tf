module "alb_ingress" {
  source                     = "./alb_ingress"
  eks_cluster_name           = local.cluster_name
  oidc_provider_arn          = try(data.terraform_remote_state.infra.outputs.cluster_oidc_provider_arn, null)
  aws_region                 = var.aws_region
  vpc_id                     = try(data.terraform_remote_state.infra.outputs.vpc_id, null)
}
