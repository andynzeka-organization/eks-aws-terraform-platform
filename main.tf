module "vpc" {
  source               = "./modules/vpc"
  name                 = var.project_name
  cidr_block           = var.vpc_cidr
  azs                  = local.azs_final
  public_subnet_cidrs  = local.public_subnet_cidrs_final
  private_subnet_cidrs = local.private_subnet_cidrs_final
  enable_nat_per_az    = var.enable_nat_per_az
  tags                 = var.tags
  cluster_name_for_tag = var.eks_cluster_name
  
}


module "eks" {
  source           = "./modules/eks"
  eks_cluster_name = var.eks_cluster_name
  region           = var.aws_region
  subnet_ids       = module.vpc.public_subnet_ids
  disk_size  = var.disk_size
  tags       = var.tags
  # enable_argocd_irsa = var.enable_argocd_irsa
  # cluster_version    = var.cluster_version
  eks_additional_sg_ids = [aws_security_group.eks_custom.id]
  depends_on = [ module.vpc ]

}


# module "platform" {
#   source           = "./apps/platform"
#   vpc_id           = module.vpc.vpc_id
#   eks_cluster_name = var.eks_cluster_name
#   aws_region       = var.aws_region
# }

data "aws_availability_zones" "available" {
  state = "available"
}


locals {
  azs_final = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 2)

  # Derive subnets if not provided: /20s from the VPC /16 by default
  public_subnets_derived  = [for i in range(length(local.azs_final)) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets_derived = [for i in range(length(local.azs_final)) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  public_subnet_cidrs_final  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : local.public_subnets_derived
  private_subnet_cidrs_final = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : local.private_subnets_derived
}

# module "platform" {
#   source           = "./apps/platform"
#   eks_cluster_name = var.eks_cluster_name
#   aws_region       = var.aws_region
#   # tags             = var.tags
# }

# resource "null_resource" "remove_ingress_finalizers" {
#   provisioner "local-exec" {
#     command = <<EOT
# kubectl patch ingress ${module.platform.argocd_ingress_name} -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge || true
# kubectl patch ingress ${module.platform.grafana_ingress_name} -n monitoring -p '{"metadata":{"finalizers":null}}' --type=merge || true
# EOT
#   }

#   triggers = { always_run = timestamp() }

#   depends_on = [
#     module.platform
#   ]
# }
