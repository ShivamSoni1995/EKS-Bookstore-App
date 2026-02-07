# GitHub Actions OIDC Provider
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Project = "bookstore"
  }
}

# IAM Role for GitHub Actions - optimized for cost efficiency
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-bookstore-role"
  max_session_duration = 3600  # 1 hour max session for cost control

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Replace with your actual GitHub username/org
            "token.actions.githubusercontent.com:sub" = "repo:ShivamSoni1995/EKS-Bookstore-App:*"
          }
        }
      }
    ]
  })

  tags = {
    Project = "bookstore"
    CostCenter = "engineering"
    Environment = "production"
  }
}

# Policy for ECR access - scoped to specific repositories for cost efficiency
resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "github-actions-ecr-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:GetRepositoryPolicy"
        ]
        Resource = [
          aws_ecr_repository.api.arn,
          aws_ecr_repository.ui.arn
        ]
      }
    ]
  })
}

# Policy for EKS access - scoped to specific cluster for cost efficiency
resource "aws_iam_role_policy" "github_actions_eks" {
  name = "github-actions-eks-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:ListClusters"
        ]
        Resource = "*"
        # Note: ListClusters cannot be scoped to specific resources
      }
    ]
  })
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}