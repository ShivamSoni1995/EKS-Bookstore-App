module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  eks_managed_node_groups = {
    bookstore_nodes = {
      name = "bookstore-node-group"

      instance_types = var.node_instance_types

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      labels = {
        Environment = "production"
        Project     = "bookstore"
      }
    }
  }

  # Enable IRSA
  enable_irsa = true

  # Cluster access
  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.github_actions_role.arn
      username = "github-actions"
      groups   = ["system:masters"]
    },
  ]

  tags = {
    Environment = "production"
    Project     = "bookstore"
  }
}