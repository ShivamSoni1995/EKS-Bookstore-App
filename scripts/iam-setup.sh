#!/bin/bash
# iam-setup.sh - Set up all required IAM roles for EKS

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CLUSTER_NAME="bookstore-cluster"
REGION="us-east-1"

echo "========================================"
echo "IAM Setup for EKS Cluster"
echo "========================================"
echo "Account ID: $ACCOUNT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# 1. Create EKS Cluster Service Role
echo "Creating EKS Cluster Service Role..."
cat > /tmp/eks-cluster-trust-policy.json << 'INNER_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
INNER_EOF

aws iam create-role \
  --role-name eksClusterServiceRole \
  --assume-role-policy-document file:///tmp/eks-cluster-trust-policy.json \
  --description "IAM role for EKS cluster" 2>/dev/null || echo "Role already exists"

aws iam attach-role-policy \
  --role-name eksClusterServiceRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || echo "Policy already attached"

echo "✓ EKS Cluster Service Role created"

# 2. Create EKS Node Group Role
echo "Creating EKS Node Group Role..."
cat > /tmp/eks-nodegroup-trust-policy.json << 'INNER_EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
INNER_EOF

aws iam create-role \
  --role-name eksNodeGroupRole \
  --assume-role-policy-document file:///tmp/eks-nodegroup-trust-policy.json \
  --description "IAM role for EKS node group" 2>/dev/null || echo "Role already exists"

aws iam attach-role-policy \
  --role-name eksNodeGroupRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || echo "Policy already attached"

aws iam attach-role-policy \
  --role-name eksNodeGroupRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || echo "Policy already attached"

aws iam attach-role-policy \
  --role-name eksNodeGroupRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || echo "Policy already attached"

echo "✓ EKS Node Group Role created"

# 3. Create GitHub Actions User
echo "Creating GitHub Actions User..."
cat > /tmp/github-actions-policy.json << 'INNER_EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "eks:DescribeCluster",
                "eks:ListClusters",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
INNER_EOF

aws iam create-user --user-name github-actions-user 2>/dev/null || echo "User already exists"

aws iam create-policy \
  --policy-name GitHubActionsEKSPolicy \
  --policy-document file:///tmp/github-actions-policy.json \
  --description "Policy for GitHub Actions to access EKS" 2>/dev/null || echo "Policy already exists"

aws iam attach-user-policy \
  --user-name github-actions-user \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/GitHubActionsEKSPolicy 2>/dev/null || echo "Policy already attached"

echo "✓ GitHub Actions User created"

# 4. Create access keys for GitHub Actions
echo ""
echo "Creating access keys for GitHub Actions..."
aws iam create-access-key --user-name github-actions-user > /tmp/github-actions-keys.json 2>&1 || echo "Keys may already exist"

if [ -f /tmp/github-actions-keys.json ] && grep -q "AccessKeyId" /tmp/github-actions-keys.json; then
  ACCESS_KEY=$(cat /tmp/github-actions-keys.json | grep AccessKeyId | cut -d'"' -f4)
  SECRET_KEY=$(cat /tmp/github-actions-keys.json | grep SecretAccessKey | cut -d'"' -f4)
  
  echo ""
  echo "========================================"
  echo "IMPORTANT: Save these credentials!"
  echo "========================================"
  echo "AWS_ACCESS_KEY_ID: $ACCESS_KEY"
  echo "AWS_SECRET_ACCESS_KEY: $SECRET_KEY"
  echo ""
  echo "Add these to your GitHub repository secrets:"
  echo "- AWS_ACCESS_KEY_ID"
  echo "- AWS_SECRET_ACCESS_KEY"
  echo "========================================"
fi

# Clean up temporary files
rm -f /tmp/eks-cluster-trust-policy.json
rm -f /tmp/eks-nodegroup-trust-policy.json
rm -f /tmp/github-actions-policy.json
rm -f /tmp/github-actions-keys.json

echo ""
echo "✓ IAM setup completed successfully!"
echo ""
echo "Summary of created roles:"
echo "- eksClusterServiceRole (arn:aws:iam::${ACCOUNT_ID}:role/eksClusterServiceRole)"
echo "- eksNodeGroupRole (arn:aws:iam::${ACCOUNT_ID}:role/eksNodeGroupRole)"
echo "- github-actions-user"
echo ""
echo "Next step: Create EKS cluster using eksctl or AWS console"
