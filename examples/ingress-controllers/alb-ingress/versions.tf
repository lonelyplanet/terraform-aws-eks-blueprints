terraform {
  backend "remote" {
    organization = "RVStandard"

    workspaces {
      name = "lonelyplanet-digital-sandbox"
    }
  }

    required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.5.1"
    }
  }
}
  