provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "zenobi-terraform-bucket"
    key    = "terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  cluster_name = coalesce(var.cluster_name, try(data.terraform_remote_state.infra.outputs.eks_cluster_name, null))
}

data "aws_eks_cluster" "this" { name = local.cluster_name }
data "aws_eks_cluster_auth" "this" { name = local.cluster_name }

# Discover account ID for building the OIDC provider ARN dynamically
data "aws_caller_identity" "current" {}

# If the EKS data source exposes subnet_ids/vpc_id, derive VPC ID. Fallback via subnet lookup.
locals {
  # EKS data source returns subnet_ids as a set; convert to a list and take a stable element
  eks_subnet_ids    = try(data.aws_eks_cluster.this.vpc_config[0].subnet_ids, [])
  eks_subnet_ids_ls = try(tolist(local.eks_subnet_ids), [])
  any_subnet_id     = length(local.eks_subnet_ids_ls) > 0 ? element(sort(local.eks_subnet_ids_ls), 0) : null
}

data "aws_subnet" "cluster_subnet" {
  count = local.any_subnet_id != null ? 1 : 0
  id    = local.any_subnet_id
}

# Auto-derived values to avoid manual tfvars or remote state coupling
locals {
  eks_oidc_issuer_no_scheme = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn_auto    = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.eks_oidc_issuer_no_scheme}"

  vpc_id_auto = coalesce(
    try(data.aws_eks_cluster.this.vpc_config[0].vpc_id, null),
    try(data.aws_subnet.cluster_subnet[0].vpc_id, null)
  )
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
