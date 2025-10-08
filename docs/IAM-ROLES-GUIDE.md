# IAM Roles and Permissions Guide

## Required IAM Roles

### 1. EKS Cluster Service Role
- **Name**: `eksClusterServiceRole`
- **Purpose**: Allows EKS to manage AWS resources
- **Managed Policy**: `AmazonEKSClusterPolicy`

### 2. EKS Node Group Role
- **Name**: `eksNodeGroupRole`
- **Purpose**: Allows worker nodes to access AWS services
- **Managed Policies**:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`

### 3. AWS Load Balancer Controller Role
- **Name**: `AmazonEKSLoadBalancerControllerRole`
- **Purpose**: Creates and manages Application Load Balancers
- **Custom Policy**: `AWSLoadBalancerControllerIAMPolicy`
- **Authentication**: OIDC (no long-term credentials)

### 4. GitHub Actions User
- **Name**: `github-actions-user`
- **Purpose**: Allows CI/CD pipeline to deploy to EKS
- **Custom Policy**: `GitHubActionsEKSPolicy`

## Setup Order

1. Run `scripts/iam-setup.sh` to create roles 1, 2, and 4
2. Create EKS cluster with the created roles
3. Run `scripts/setup-aws-load-balancer-controller.sh` for role 3

## Verification

```bash
# Check roles exist
aws iam get-role --role-name eksClusterServiceRole
aws iam get-role --role-name eksNodeGroupRole
aws iam get-role --role-name AmazonEKSLoadBalancerControllerRole

# Check user
aws iam get-user --user-name github-actions-user
```
