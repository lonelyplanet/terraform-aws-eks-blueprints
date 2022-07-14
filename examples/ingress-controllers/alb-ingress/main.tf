provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

data "aws_availability_zones" "available" {}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source  = "../../.."
  # source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.0.9"

  cluster_name    = local.name
  cluster_version = "1.21"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.large"]
      min_size        = 2
      subnet_ids      = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  # source  = "../../../modules/kubernetes-addons"
  source = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/kubernetes-addons?ref=v4.0.9"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

  # EKS Managed Add-ons
  enable_amazon_eks_coredns    = true
  enable_amazon_eks_kube_proxy = true

  # Add-ons
  enable_aws_load_balancer_controller = true
  enable_traefik                      = true
  enable_external_dns                 = true
  eks_cluster_domain                  = var.eks_cluster_domain
  




  tags = local.tags
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

resource "aws_ecr_repository" "hello_world_1" {
  name    = "lonelyplanet/hello-world-1"
}

resource "aws_ecr_repository" "hello_world_2" {
  name    = "lonelyplanet/hello-world-2"
}

locals {
  sandbox_redventures_io_zone_id  = "Z08254026D5U6GFLW2PV"
  ingress_alb_dns                 = "lonelyplanet-external-914325800.us-west-2.elb.amazonaws.com"
  ingress_alb_zone_id             = "Z1H1FL5HABSF5"


}

resource "aws_route53_record" "hello_world_1" {
  zone_id = local.sandbox_redventures_io_zone_id
  name    = "hello-world-1"
  type    = "A"

  alias {
    name                    = local.ingress_alb_dns
    zone_id                 = local.ingress_alb_zone_id
    evaluate_target_health  = false
  }
}

resource "aws_route53_record" "hello_world_2" {
  zone_id = local.sandbox_redventures_io_zone_id
  name    = "hello-world-2"
  type    = "A"

  alias {
    name                    = local.ingress_alb_dns
    zone_id                 = local.ingress_alb_zone_id
    evaluate_target_health  = false
  }
}

resource "aws_wafv2_web_acl" "alb_acl" {
  name  = "alb-ingress-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name      = "rate-based-rule"
    priority  = 0
    
    action {
      count {}
    }
      statement {
        rate_based_statement {
          limit               = 100
          aggregate_key_type  = "IP"
        }
      }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-based-rule"
      sampled_requests_enabled   = true
    }
  }


  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "alb-ingress-web-acl"
    sampled_requests_enabled   = true
  }
}
