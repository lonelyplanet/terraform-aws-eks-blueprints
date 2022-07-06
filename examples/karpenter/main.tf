













#
#
#
# │ Error: Kubernetes cluster unreachable: the server has asked for the client to provide credentials                                                                                                                                                           │
# │   with module.eks_blueprints_kubernetes_addons.module.aws_load_balancer_controller[0].module.helm_addon.helm_release.addon[0],
# │   on ../../modules/kubernetes-addons/helm-addon/main.tf line 1, in resource "helm_release" "addon":
# │    1: resource "helm_release" "addon" {
#
# It is likely that an IAM role will be needed to allow the cluster to create load balancers
#
#
#




























provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
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
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks_blueprints.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.eks_cluster_id]
  }
}

data "aws_availability_zones" "available" {}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  node_group_name = "managed-ondemand"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
}

#---------------------------------------------------------------
# IAM roles
#---------------------------------------------------------------

data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

  }
}

resource "aws_iam_role" "eks_load_balancer_controller_role" {
  name = "eks_load_balancer_controller_role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
}

data "aws_iam_policy_document" "eks_create_load_balancer_policy_document" {
  source_json = file("${path.module}/load_balancer_iam_policy.json")
}

resource "aws_iam_policy" "eks_create_load_balancer_policy" {
  name   = "eks_create_load_balancer_policy"
  policy = data.aws_iam_policy_document.eks_create_load_balancer_policy_document.json
}
resource "aws_iam_role_policy_attachment" "eks_create_load_balancer_controller_attachment" {
  role = aws_iam_role.eks_load_balancer_controller_role.name
  policy_arn = aws_iam_policy.eks_create_load_balancer_policy.arn
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks_blueprints" {
  source = "../.."

  cluster_name    = local.name
  cluster_version = "1.22"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  #----------------------------------------------------------------------------------------------------------#
  # Security groups used in this module created by the upstream modules terraform-aws-eks (https://github.com/terraform-aws-modules/terraform-aws-eks).
  #   Upstream module implemented Security groups based on the best practices doc https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html.
  #   So, by default the security groups are restrictive. Users needs to enable rules for specific ports required for App requirement or Add-ons
  #   See the notes below for each rule used in these examples
  #----------------------------------------------------------------------------------------------------------#
  node_security_group_additional_rules = {
    # Extend node-to-node security group rules. Recommended and required for the Add-ons
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Recommended outbound traffic for Node groups
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Allows Control Plane Nodes to talk to Worker nodes on Karpenter ports.
    # This can be extended further to specific port based on the requirement for others Add-on e.g., metrics-server 4443, spark-operator 8080, etc.
    # Change this according to your security requirements if needed
    ingress_nodes_karpenter_port = {
      description                   = "Cluster API to Nodegroup for Karpenter"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  # Add karpenter.sh/discovery tag so that we can use this as securityGroupSelector in karpenter provisioner
  node_security_group_tags = {
    "karpenter.sh/discovery/${local.name}" = local.name
  }

<<<<<<< Updated upstream
  # EKS MANAGED NODE GROUPS
  # We recommend to have a MNG to place your critical workloads and add-ons
  # Then rely on Karpenter to scale your workloads
  # You can also make uses on nodeSelector and Taints/tolerations to spread workloads on MNG or Karpenter provisioners
  managed_node_groups = {
    mg_5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.large"]

      subnet_ids   = module.vpc.private_subnets
      max_size     = 2
      desired_size = 1
      min_size     = 1
      update_config = [{
        max_unavailable_percentage = 30
      }]

      # Launch template configuration
      create_launch_template = true              # false will use the default launch template
      launch_template_os     = "amazonlinux2eks" # amazonlinux2eks or bottlerocket
=======
  # Self-managed Node Group
  # Karpenter requires one node to get up and running
  self_managed_node_groups = {
    self_mg_5 = {
      node_group_name    = local.node_group_name
      launch_template_os = "bottlerocket"
      max_size           = 1
      subnet_ids         = module.vpc.private_subnets
>>>>>>> Stashed changes
    }
  }

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source = "../../modules/kubernetes-addons"

  eks_cluster_id       = module.eks_blueprints.eks_cluster_id
  eks_cluster_endpoint = module.eks_blueprints.eks_cluster_endpoint
  eks_oidc_provider    = module.eks_blueprints.oidc_provider
  eks_cluster_version  = module.eks_blueprints.eks_cluster_version

<<<<<<< Updated upstream
  enable_karpenter                    = true
  enable_aws_node_termination_handler = true
=======
  enable_karpenter = true
  enable_metrics_server = true
  enable_aws_load_balancer_controller = true
  enable_ingress_nginx = true

  aws_load_balancer_controller_helm_config = {
    values = [templatefile("${path.module}/load_balancer_values.tftpl", { arn = aws_iam_role.eks_load_balancer_controller_role.arn })]
  }
  ingress_nginx_helm_config = {
    version = "4.0.17"
    values  = [templatefile("${path.module}/nginx_values.tftpl", {})]
  }
>>>>>>> Stashed changes

  tags = local.tags

}

# Creates Launch templates for Karpenter
# Launch template outputs will be used in Karpenter Provisioners yaml files. Checkout this examples/karpenter/provisioners/default_provisioner_with_launch_templates.yaml
module "karpenter_launch_templates" {
  source = "../../modules/launch-templates"

  eks_cluster_id = module.eks_blueprints.eks_cluster_id

  launch_template_config = {
    linux = {
      ami                    = data.aws_ami.bottlerocket.id
      launch_template_prefix = "karpenter"
      iam_instance_profile   = module.eks_blueprints.managed_node_group_iam_instance_profile_id[0]
      vpc_security_group_ids = [module.eks_blueprints.worker_node_security_group_id]
      block_device_mappings = [
        {
          device_name = "/dev/xvda"
          volume_type = "gp3"
          volume_size = 200
        }
      ]
    }

    bottlerocket = {
      ami                    = data.aws_ami.bottlerocket.id
      launch_template_os     = "bottlerocket"
      launch_template_prefix = "bottle"
      iam_instance_profile   = module.eks_blueprints.managed_node_group_iam_instance_profile_id[0]
      vpc_security_group_ids = [module.eks_blueprints.worker_node_security_group_id]
      block_device_mappings = [
        {
          device_name = "/dev/xvda"
          volume_type = "gp3"
          volume_size = 200
        }
      ]
    }
  }

  tags = merge(local.tags, { Name = "karpenter" })
}

# Deploying default provisioner and default-lt (using launch template) for Karpenter autoscaler
data "kubectl_path_documents" "karpenter_provisioners" {
  pattern = "${path.module}/provisioners/default_provisioner*.yaml" # without launch template
  vars = {
    azs                     = join(",", local.azs)
    iam-instance-profile-id = "${local.name}-${local.node_group_name}"
    eks-cluster-id          = local.name
    eks-vpc_name            = local.name
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  for_each  = toset(data.kubectl_path_documents.karpenter_provisioners.documents)
  yaml_body = each.value

  depends_on = [module.eks_blueprints_kubernetes_addons]
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

data "aws_ami" "bottlerocket" {
  owners      = ["amazon"]
  most_recent = true

  filter {
    name   = "name"
    values = ["bottlerocket-aws-k8s-${module.eks_blueprints.eks_cluster_version}-x86_64-*"]
  }
}
