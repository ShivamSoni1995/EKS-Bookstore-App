#!/bin/bash
# quick-start.sh - One-command deployment

set -e

echo "========================================"
echo "EKS BookStore Quick Start"
echo "========================================"
echo ""
echo "This script will:"
echo "1. Create IAM roles"
echo "2. Create EKS cluster"
echo "3. Install AWS Load Balancer Controller"
echo "4. Deploy the application"
echo ""
read -p "Do you want to continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Variables
CLUSTER_NAME="bookstore-cluster"
REGION="us-east-1"

echo ""
echo "Using:"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# Step 1: IAM Setup
echo "Step 1/4: Setting up IAM roles..."
cd scripts
./iam-setup.sh
cd ..

echo ""
read -p "Press enter to continue to EKS cluster creation..."

# Step 2: Create EKS Cluster
echo ""
echo "Step 2/4: Creating EKS cluster (this will take 15-20 minutes)..."
eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --nodegroup-name bookstore-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --managed

echo "✓ EKS cluster created"

# Step 3: Install AWS Load Balancer Controller
echo ""
echo "Step 3/4: Installing AWS Load Balancer Controller..."
cd scripts
./setup-aws-load-balancer-controller.sh
cd ..

echo "✓ AWS Load Balancer Controller installed"

# Step 4: Deploy Application
echo ""
echo "Step 4/4: Deploying BookStore application..."
cd scripts
./deploy.sh
cd ..

echo ""
echo "========================================"
echo "✓ Quick Start Complete!"
echo "========================================"
echo ""
echo "Your application should be accessible in 2-3 minutes."
echo "Run this command to get the URL:"
echo "kubectl get ingress bookstore-ingress -n bookstore"
