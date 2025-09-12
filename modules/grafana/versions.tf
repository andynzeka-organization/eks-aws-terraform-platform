terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.29" }
    helm       = { source = "hashicorp/helm",       version = ">= 2.11" }
    random     = { source = "hashicorp/random",     version = ">= 3.5" }
  }
}

