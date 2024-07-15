terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region  = var.region
  profile = "selfmgmt"
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubernetes" {
  alias                  = "aws"
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.kubernetes.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.default.token
  load_config_file       = false
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

data "aws_vpc" "poc" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:SubnetType"
    values = ["Private"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:SubnetType"
    values = ["Public"]
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

locals {
  name   = "poc-${basename(path.cwd)}"
  region = var.region

  vpc_cidr = data.aws_vpc.poc.cidr_block
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  istio_charts_url = "https://istio-release.storage.googleapis.com/charts"

  tags = {
    Product = local.name
  }
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = " ~> 20.17.0"

  cluster_name    = local.name
  cluster_version = "1.30"

  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    coredns                = {}
    eks-pod-identity-agent = {}
    kube-proxy             = {}
    vpc-cni                = {}
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = data.aws_subnets.private.ids
  control_plane_subnet_ids = data.aws_subnets.private.ids

  eks_managed_node_groups = {
    karpenterX64 = {
      ami_type       = "BOTTLEROCKET_x86_64"
      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
    karpenterArm = {
      ami_type       = "BOTTLEROCKET_ARM_64"
      instance_types = ["t4g.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
    karpenterGPU = {
      ami_type       = "BOTTLEROCKET_ARM_64_NVIDIA"
      instance_types = ["g5g.xlarge"]

      min_size     = 1
      max_size     = 2
      desired_size = 1

      taints = {
        # This Taint aims to keep just EKS Addons and Karpenter running on this MNG
        # The pods that do not tolerate this taint should run on nodes created by Karpenter
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        },
      }
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })
}