terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.29" }
    helm = { source = "hashicorp/helm", version = ">= 2.11" }
  }
  backend "s3" {
    bucket         = "zenobi-terraform-bucket"
    key            = "apps/grafana/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "zenobi-terraform-eks-state-lock"
    encrypt        = true
  }
}

