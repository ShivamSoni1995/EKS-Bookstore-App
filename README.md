# BookStore App EKS Deployment with Ingress and CI/CD

Complete deployment solution for a BookStore application on Amazon EKS with AWS Load Balancer Controller and GitHub Actions CI/CD.

## 🏗️ Architecture

- **Frontend**: `shivamsoni1995/bookapp-ui` - Port 80
- **Backend**: `shivamsoni1995/bookapp-api` - Port 3000
- **Ingress**: AWS Application Load Balancer
- **CI/CD**: GitHub Actions for automated UI deployments

## 🚀 Quick Start

### Prerequisites

- AWS CLI configured
- kubectl installed
- eksctl installed
- Helm 3.x installed
- Docker Hub account

### Step 1: Set Up IAM Roles

```bash
cd scripts
chmod +x *.sh
./iam-setup.sh
```

### Step 2: Create EKS Cluster

```bash
eksctl create cluster \
  --name bookstore-cluster \
  --region us-east-1 \
  --nodegroup-name bookstore-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --managed
```

### Step 3: Install AWS Load Balancer Controller

```bash
./setup-aws-load-balancer-controller.sh
```

### Step 4: Deploy Application

```bash
./deploy.sh
```

### Step 5: Get Your Application URL

```bash
kubectl get ingress bookstore-ingress -n bookstore -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}'
```

### Step 6: Set Up CI/CD

1. Copy `github-workflows/deploy-ui.yml` to `.github/workflows/` in your repository
2. Add GitHub Secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `DOCKER_USERNAME`
   - `DOCKER_TOKEN`
3. Update workflow variables (cluster name, region)

## 📋 Accessing Your Application

- **UI**: `http://YOUR-ALB-DNS.elb.amazonaws.com/`
- **API**: `http://YOUR-ALB-DNS.elb.amazonaws.com/api/`

## 🔧 Management Commands

```bash
# View all resources
kubectl get all -n bookstore

# Check ingress status
kubectl get ingress -n bookstore

# View logs
kubectl logs -f deployment/bookapp-ui -n bookstore
kubectl logs -f deployment/bookapp-api -n bookstore

# Scale deployments
kubectl scale deployment bookapp-ui --replicas=3 -n bookstore
```

## 🧹 Cleanup

```bash
# Delete application
kubectl delete namespace bookstore

# Delete AWS Load Balancer Controller (optional)
helm uninstall aws-load-balancer-controller -n kube-system

# Delete EKS cluster
eksctl delete cluster --name bookstore-cluster --region us-east-1
```

## 📚 Documentation

- [IAM Roles Guide](docs/IAM-ROLES-GUIDE.md)
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md)

## 📝 License

MIT License
