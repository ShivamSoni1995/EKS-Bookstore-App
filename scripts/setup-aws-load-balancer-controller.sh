#!/bin/bash
# setup-aws-load-balancer-controller.sh

set -e

# Variables - Update these
CLUSTER_NAME="bookstore-cluster"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "========================================"
echo "AWS Load Balancer Controller Setup"
echo "========================================"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo ""

# 1. Create IAM OIDC provider for the cluster
echo "Creating IAM OIDC provider..."
eksctl utils associate-iam-oidc-provider \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --approve

echo "✓ OIDC provider created"

# 2. Download IAM policy
echo "Downloading IAM policy for AWS Load Balancer Controller..."
curl -s -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# 3. Create IAM policy
echo "Creating IAM policy..."
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file:///tmp/iam-policy.json \
    --description "IAM policy for AWS Load Balancer Controller" 2>/dev/null || echo "Policy already exists"

echo "✓ IAM policy created"

# 4. Create IAM service account
echo "Creating IAM service account..."
eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --role-name AmazonEKSLoadBalancerControllerRole \
    --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --approve \
    --region=$REGION \
    --override-existing-serviceaccounts

echo "✓ IAM service account created"

# 5. Add EKS Helm repository
echo "Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "✓ Helm repository added"

# 6. Install AWS Load Balancer Controller
echo "Installing AWS Load Balancer Controller..."

# Get VPC ID
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query cluster.resourcesVpcConfig.vpcId --output text)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=$CLUSTER_NAME \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region=$REGION \
    --set vpcId=$VPC_ID

echo "✓ AWS Load Balancer Controller installed"

# 7. Verify installation
echo "Verifying installation..."
kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n kube-system

echo ""
echo "========================================"
echo "✓ Setup completed successfully!"
echo "========================================"
echo ""
echo "Verify the controller is running:"
echo "kubectl get deployment -n kube-system aws-load-balancer-controller"
echo ""
echo "Next step: Deploy your application"
echo "kubectl apply -f kubernetes/bookstore-deployment.yml"

# Clean up
rm -f /tmp/iam-policy.json
