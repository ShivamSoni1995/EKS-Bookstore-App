
# 📚 EKS Bookstore App

---

## Manual Setup Before `bootstrap.sh`

Before running the automated deployment script, you must perform these manual steps:

1. **Initialize Terraform:**
   ```bash
   cd terraform
   terraform init
   ```

2. **First Terraform Apply (create cluster, skip aws-auth):**
   - Edit `eks-cluster.tf` and set:
     ```
     manage_aws_auth_configmap = false
     ```
   - Then run:
     ```bash
     terraform apply
     ```

3. **Second Terraform Apply (manage aws-auth):**
   - Edit `eks-cluster.tf` and set:
     ```
     manage_aws_auth_configmap = true
     ```
   - Then run:
     ```bash
     terraform apply
     ```

4. **Update GitHub Secret:**
   - Copy the new `github_actions_role_arn` from:
     ```bash
     terraform output github_actions_role_arn
     ```
   - Update the `AWS_ROLE_ARN` secret in your GitHub repository settings.

5. **(Optional) Update `cd.yaml` if cluster name changed:**
   - If the EKS cluster name changed, update the `EKS_CLUSTER_NAME` in `.github/workflows/cd.yaml`.

After these steps, you can safely run:
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

---

A full-stack bookstore web application deployed on **Amazon EKS** with automated CI/CD via **GitHub Actions**, infrastructure-as-code with **Terraform**, and cluster monitoring with **Prometheus + Grafana**.

![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?logo=amazon-aws)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=github-actions)

---

## Architecture

```
                    ┌───────────────────────────────────────────────────┐
┌──────────┐        │  AWS (us-east-1)                                  │
│  GitHub  │  OIDC  │  ┌─────────┐    ┌──────────────────────────────┐  │
│  Actions ├────────┤  │   ECR   │    │  EKS Cluster (K8s 1.28)     │  │
│  CI / CD │        │  │ api/ui  │    │                              │  │
└──────────┘        │  └─────────┘    │  ┌───────┐    ┌───────┐     │  │
                    │                 │  │  API  │    │  UI   │     │  │
┌──────────┐        │  ┌──────────┐   │  │ Flask │    │ React │     │  │
│  Users   ├────────┤  │   ALB   ├───▶│  └───┬───┘    └───┬───┘     │  │
│ (browser)│        │  │(internet)│   │      └─────┬──────┘         │  │
└──────────┘        │  └──────────┘   │      Ingress│               │  │
                    │                 │  ┌─────────┴──────────┐     │  │
                    │                 │  │ Monitoring Stack    │     │  │
                    │                 │  │ Prometheus + Grafana│     │  │
                    │                 │  └────────────────────┘     │  │
                    │                 └──────────────────────────────┘  │
                    │  VPC 10.0.0.0/16 · 2 AZs · Public subnets only  │
                    └───────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | React 19, React Router 7, served via Node.js (`server.js`) |
| **Backend** | Python 3.11, Flask 2.2.3, Flask-CORS |
| **Containers** | Docker (multi-stage build for UI, slim image for API) |
| **Orchestration** | Amazon EKS (Kubernetes 1.28) |
| **Infrastructure** | Terraform (AWS provider ~5.0, EKS module ~19.0) |
| **CI/CD** | GitHub Actions with OIDC authentication (no stored keys) |
| **Ingress** | AWS Application Load Balancer (via aws-load-balancer-controller) |
| **Registry** | Amazon ECR (bookstore-api, bookstore-ui) |
| **Monitoring** | kube-prometheus-stack (Prometheus, Grafana, Alertmanager) |

---

## Project Structure

```
├── api/                          # Flask REST API
│   ├── Dockerfile                # Python 3.11-slim, FLASK_APP=main.py
│   ├── main.py                   # Endpoints: /api/health, /api/products, /api/categories
│   ├── requirements.txt          # flask, flask-cors
│   └── test_main.py              # Pytest unit tests
│
├── ui/                           # React frontend
│   ├── Dockerfile                # Multi-stage: node:20-alpine build → production
│   ├── server.js                 # Express server, proxies /api/ → http://api (K8s service)
│   ├── package.json              # React 19, react-router-dom, serve-handler
│   └── src/
│       ├── App.js                # BrowserRouter with routes
│       ├── components/           # Navbar, Footer, Hero
│       └── pages/                # Home, ProductList, ProductDetail, Cart
│
├── k8s/                          # Kubernetes manifests
│   ├── namespace.yaml            # bookstore namespace
│   ├── api-deployment.yaml       # API deployment + ClusterIP service (port 5000)
│   ├── ui-deployment.yaml        # UI deployment + ClusterIP service (port 3000)
│   ├── ingress.yaml              # ALB ingress: /api/* → api, /* → ui
│   └── prometheus-values.yaml    # Helm values for kube-prometheus-stack
│
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                   # Providers, random cluster name suffix
│   ├── variables.tf              # Instance type, node count, region
│   ├── vpc.tf                    # VPC, 2 AZs, public subnets, no NAT gateway
│   ├── eks-cluster.tf            # EKS cluster, SPOT node group, IRSA, aws-auth
│   ├── ecr.tf                    # ECR repos with lifecycle (keep last 5 images)
│   ├── iam.tf                    # GitHub Actions OIDC provider + IAM role
│   ├── lb-controller.tf          # LB controller IRSA role
│   ├── lb-controller-policy.json # IAM policy v2.12.0
│   └── outputs.tf                # Cluster name, ECR URLs, role ARNs
│
├── .github/workflows/
│   ├── ci.yaml                   # CI: push to develop → test → build → push to ECR
│   └── cd.yaml                   # CD: push to main → build → deploy to EKS
│
├── bootstrap.sh                  # Automated deployment script (post-terraform)
└── claude.md                     # AI reference document for project context
```

---

## Prerequisites

- **AWS CLI** v2 configured with appropriate credentials
- **Terraform** >= 1.0
- **kubectl** v1.28+
- **Helm** v3
- **Docker**
- **Node.js** 18+ (for local UI development)
- **Python** 3.11+ (for local API development)

---

## Getting Started

### 1. Provision Infrastructure

```bash
cd terraform
terraform init
terraform apply
```

> **Note**: On first apply, `manage_aws_auth_configmap` should be `false`. After the cluster is created, set it to `true` and run `terraform apply` again.

### 2. Deploy Everything

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

The bootstrap script automatically:
1. Reads Terraform outputs (cluster name, ECR URLs, role ARNs)
2. Configures `kubectl` for the EKS cluster
3. Builds and pushes Docker images to ECR
4. Deploys K8s manifests (namespace, deployments, services, ingress)
5. Installs AWS Load Balancer Controller via Helm
6. Installs the monitoring stack (Prometheus + Grafana)

### 3. Access the Application

```bash
# Get the ALB URL
kubectl get ingress -n bookstore

# Open in browser
# http://<ALB_DNS_NAME>/
```

---

## CI/CD Pipeline

### Branch Strategy

| Branch | Trigger | Pipeline |
|--------|---------|----------|
| `develop` | Push | **CI** — Lint, test, build, push to ECR |
| `main` | Push / Merge | **CD** — Build, push, deploy to EKS |

### CI Pipeline (`.github/workflows/ci.yaml`)

```
Push to develop
  ├─► test-backend    (pytest)
  ├─► test-frontend   (jest)
  └─► build-and-push  (Docker build → ECR with SHA tag)
        ↑ depends on both tests passing
```

### CD Pipeline (`.github/workflows/cd.yaml`)

```
Push to main
  └─► build-and-deploy
        ├── Build & push images (SHA + latest + production tags)
        ├── Update kubeconfig for EKS
        ├── sed replace image tags in manifests
        ├── kubectl apply all manifests
        └── kubectl rollout status (wait for completion)
```

### Required GitHub Secret

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | ARN of the GitHub Actions IAM role (from `terraform output github_actions_role_arn`) |

---

## Local Development

### API

```bash
cd api
pip install -r requirements.txt
export FLASK_APP=main.py
flask run --port 5000
# → http://localhost:5000/api/health
```

### UI

```bash
cd ui
npm install
npm start
# → http://localhost:3000
```

---

## Monitoring

The cluster runs **kube-prometheus-stack** in the `monitoring` namespace.

### Access Grafana

```bash
kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring
# → http://localhost:3001
# Login: admin / bookstore-admin
```

### Access Prometheus

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# → http://localhost:9090
```

### Useful PromQL Queries

```promql
# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="bookstore"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_working_set_bytes{namespace="bookstore"}) by (pod)

# HTTP request rate (if instrumented)
rate(flask_http_request_total[5m])

# Node count
count(kube_node_info)
```

---

## Cost Optimization

This project is designed to run within a **$120 AWS free credit** budget:

| Decision | Impact |
|----------|--------|
| **SPOT** instances (t3.small) | ~60-70% cheaper than on-demand |
| **No NAT gateway** (public subnets only) | Saves ~$32/month |
| **2 Availability Zones** (not 3) | Fewer subnets/resources |
| **ECR lifecycle policy** (keep 5 images) | Minimal storage cost |
| **No persistent storage** for monitoring | Uses emptyDir |
| **Estimated total**: ~$30-40/month | ~3 months on $120 credits |

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/products` | List all products |
| GET | `/api/products/<id>` | Get product by ID |
| GET | `/api/categories` | List all categories |
| GET | `/api/categories/<id>/products` | Products by category |

---

## Useful Commands

```bash
# Connect to the cluster
aws eks update-kubeconfig --name <CLUSTER_NAME> --region us-east-1

# Check application pods
kubectl get pods -n bookstore

# Check monitoring pods
kubectl get pods -n monitoring

# View pod logs
kubectl logs -n bookstore deployment/api
kubectl logs -n bookstore deployment/ui

# View ALB ingress
kubectl get ingress -n bookstore

# LB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20

# Terraform outputs
cd terraform && terraform output
```

---

## Tear Down

```bash
# Delete Helm releases first
helm uninstall prometheus -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system

# Delete K8s resources
kubectl delete -f k8s/

# Destroy infrastructure
cd terraform
terraform destroy
```
