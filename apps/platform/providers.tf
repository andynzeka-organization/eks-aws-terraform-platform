variable "cluster_name" {
  description = "EKS cluster name (override or fallback when remote state isn't available)"
  type        = string
  default     = "demo-eks-cluster"
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "zenobi-terraform-bucket"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  cluster_name = coalesce(var.cluster_name, try(data.terraform_remote_state.infra.outputs.eks_cluster_name, null))
}

data "aws_eks_cluster" "demo-eks-cluster" { name = local.cluster_name }
data "aws_eks_cluster_auth" "demo-eks-cluster" { name = local.cluster_name }

provider "kubernetes" {
  host                   = data.aws_eks_cluster.demo-eks-cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.demo-eks-cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.demo-eks-cluster.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.demo-eks-cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.demo-eks-cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.demo-eks-cluster.token
  }
}

provider "aws" {
  region = var.aws_region
}
