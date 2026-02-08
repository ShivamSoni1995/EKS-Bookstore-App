# EKS Bookstore App - AI Reference Document

> **Purpose**: This file provides complete context for an AI assistant to understand the project state, architecture, decisions, and current deployment. Point any new AI chat to this file.

---

## Project Overview

A **bookstore web application** deployed on **Amazon EKS** with a fully automated CI/CD pipeline using GitHub Actions.

- **Repository**: `ShivamSoni1995/EKS-Bookstore-App`
- **AWS Account**: `342206309108`
- **Region**: `us-east-1`
- **Current Cluster Name**: `bookstore-eks-EFruva57` *(changes on each terraform apply due to random suffix)*

---

## Architecture

```
┌─────────────┐     ┌─────────────────────────────────────────────┐
│   GitHub     │     │              AWS (us-east-1)                │
│   Actions    │────▶│  ┌─────────┐   ┌───────────────────────┐   │
│  CI/CD       │     │  │  ECR    │   │  EKS Cluster          │   │
│  (OIDC Auth) │     │  │ api/ui  │   │  ┌─────┐  ┌─────┐    │   │
│              │     │  └─────────┘   │  │ API │  │ UI  │    │   │
└─────────────┘     │                 │  │Pod  │  │Pod  │    │   │
                    │                 │  └──┬──┘  └──┬──┘    │   │
┌─────────────┐     │                 │     └────┬───┘       │   │
│   Users      │────▶│  ┌──────────┐  │    ┌─────┴─────┐     │   │
│   Browser    │     │  │   ALB    │──▶│    │  Ingress  │     │   │
└─────────────┘     │  │(internet)│  │    └───────────┘     │   │
                    │  └──────────┘  │  ┌───────────────┐   │   │
                    │                │  │  Monitoring    │   │   │
                    │                │  │  (Prometheus   │   │   │
                    │                │  │   + Grafana)   │   │   │
                    │                │  └───────────────┘   │   │
                    │                └───────────────────────┘   │
                    │  VPC: 10.0.0.0/16 (2 AZs, public only)   │
                    └─────────────────────────────────────────────┘
```

---

## Tech Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| **Backend API** | Python 3.11, Flask 2.2.3 | File: `api/main.py`, `FLASK_APP=main.py` (NOT app.py) |
| **Frontend UI** | React 19, Node 20 | Built with CRA, served by `server.js` using `serve-handler` |
| **UI Proxy** | `http-proxy-middleware` | `server.js` proxies `/api/` to `http://api` (K8s service name) |
| **Container Runtime** | Docker | Multi-stage build for UI, slim image for API |
| **Orchestration** | Kubernetes 1.28 (EKS) | Namespace: `bookstore` |
| **Infrastructure** | Terraform | AWS provider ~5.0, EKS module ~19.0, VPC module ~5.0 |
| **CI/CD** | GitHub Actions | OIDC auth to AWS (no stored access keys) |
| **Ingress** | AWS ALB via aws-load-balancer-controller | `ingressClassName: alb`, internet-facing |
| **Monitoring** | kube-prometheus-stack | Prometheus + Grafana + Alertmanager + node-exporter |
| **DNS/Access** | ALB DNS name | No custom domain configured |

---

## Directory Structure

```
EKS-Bookstore-App/
├── bootstrap.sh                    # One-command deployment after terraform apply
├── api/
│   ├── Dockerfile                  # Python 3.11-slim, FLASK_APP=main.py
│   ├── main.py                     # Flask app with /api/health, /api/products, etc.
│   ├── requirements.txt            # flask, flask-cors, psycopg
│   └── test_main.py                # Pytest tests
├── ui/
│   ├── Dockerfile                  # Multi-stage: node:20-alpine build → production
│   ├── server.js                   # Express server with API proxy to http://api
│   ├── package.json                # React 19, react-router-dom 7
│   └── src/
│       ├── App.js                  # BrowserRouter with routes
│       ├── App.test.js             # Smoke test (no router dependency)
│       ├── components/             # Navbar, Footer, Hero
│       └── pages/                  # Home, ProductList, ProductDetail, Cart
├── k8s/
│   ├── namespace.yaml              # namespace: bookstore
│   ├── api-deployment.yaml         # 1 replica, ClusterIP service, port 5000
│   ├── ui-deployment.yaml          # 1 replica, ClusterIP service, port 3000
│   ├── ingress.yaml                # ALB ingress: /api → api:80, / → ui:80
│   └── prometheus-values.yaml      # Resource-constrained monitoring config
├── terraform/
│   ├── main.tf                     # Providers (aws, kubernetes), random suffix
│   ├── variables.tf                # t3.small, 2 nodes, SPOT
│   ├── vpc.tf                      # 2 AZs, public subnets only, no NAT gateway
│   ├── eks-cluster.tf              # EKS 1.28, IRSA enabled, aws-auth managed
│   ├── ecr.tf                      # bookstore-api & bookstore-ui repos, lifecycle 5 images
│   ├── iam.tf                      # GitHub Actions OIDC role
│   ├── lb-controller.tf            # IRSA role for AWS LB controller
│   ├── lb-controller-policy.json   # IAM policy v2.12.0 (includes DescribeListenerAttributes)
│   └── outputs.tf                  # cluster_name, ecr_urls, role_arns, region
└── .github/workflows/
    ├── ci.yaml                     # Push to develop: test → build → push to ECR
    └── cd.yaml                     # Push to main: build → push → deploy to EKS
```

---

## Cost Optimization Decisions

| Decision | Savings | Detail |
|----------|---------|--------|
| t3.small instances | ~$15/node/mo | Instead of t3.medium ($30/mo) |
| SPOT instances | ~60-70% off | vs on-demand pricing |
| 2 nodes (was 1, scaled for monitoring) | ~$15/mo total | Both SPOT |
| No NAT gateway | -$32/mo | Nodes on public subnets only |
| 2 AZs instead of 3 | Fewer resources | Less NAT/subnet cost |
| ECR lifecycle: keep 5 images | Minimal storage | Auto-expire old images |
| No persistent storage for Prometheus | -$0.50/mo | emptyDir, data lost on restart |
| **Estimated total**: ~$30-40/mo | | With $120 credits = ~3 months |

---

## CI/CD Pipeline

### CI Pipeline (`ci.yaml`) — Trigger: push to `develop`
1. **test-backend**: pip install → pytest
2. **test-frontend**: npm install → jest (smoke test only)
3. **build-and-push**: Build Docker images → push to ECR with `$GITHUB_SHA` tag

### CD Pipeline (`cd.yaml`) — Trigger: push to `main`
1. Build & push images with SHA, `latest`, and `production` tags
2. Connect to EKS cluster
3. `sed` replaces image tags in K8s manifests with new SHA
4. `kubectl apply` all manifests
5. Wait for rollout completion

### GitHub Secrets Required
| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | `arn:aws:iam::342206309108:role/github-actions-bookstore-role` *(changes on recreate)* |

### Branch Strategy
- `develop` → triggers CI (test + build)
- `main` → triggers CD (build + deploy)
- Workflow: push to develop → CI passes → merge to main → CD deploys

---

## Key Decisions & Gotchas

### Bugs That Were Fixed (remember these on recreate)
1. **`manage_aws_auth_configmap`**: Must be `false` on first `terraform apply`, then change to `true` on second apply. The ConfigMap doesn't exist before the cluster is created.
2. **Public subnet auto-assign IP**: `map_public_ip_on_launch = true` is required in vpc.tf or nodes can't reach the internet.
3. **Flask app name**: The file is `main.py`, so `ENV FLASK_APP=main.py` must be in the API Dockerfile. Without it, Flask can't find the app.
4. **K8s manifest image URLs**: Must use actual ECR URLs, not `${AWS_ACCOUNT_ID}` placeholders. The CD pipeline `sed` command must match the actual URL pattern.
5. **LB controller IAM policy**: The v2.7.1 policy is missing `ec2:GetSecurityGroupsForVpc` and `elasticloadbalancing:DescribeListenerAttributes`. Use v2.12.0 policy.
6. **t3.small pod limit**: Max 11 pods per node (ENI limit). Need 2 nodes to run app + monitoring.
7. **EBS CSI driver**: Not installed by default on EKS. Prometheus `storageSpec` set to `{}` (emptyDir) to avoid PVC stuck in Pending.
8. **Frontend test**: Cannot import `react-router-dom` in CI environment. Test simplified to smoke test without router dependency.
9. **CD pipeline sed pattern**: Must match actual ECR URLs in manifests (e.g., `342206309108.dkr.ecr.us-east-1.amazonaws.com/bookstore-api:[a-zA-Z0-9]*`), not placeholder variables.

### Helm Releases Installed Manually (not in Terraform)
| Release | Namespace | Chart |
|---------|-----------|-------|
| `aws-load-balancer-controller` | `kube-system` | `eks/aws-load-balancer-controller` |
| `prometheus` | `monitoring` | `prometheus-community/kube-prometheus-stack` |

---

## Terraform State

Terraform manages:
- VPC (2 AZs, public/private subnets, no NAT)
- EKS cluster + managed node group (SPOT, t3.small)
- ECR repositories (bookstore-api, bookstore-ui)
- IAM: GitHub Actions OIDC role + ECR/EKS policies
- IAM: LB controller IRSA role + policy
- aws-auth ConfigMap (maps GitHub Actions role to system:masters)

Terraform does **NOT** manage:
- Helm releases (LB controller, prometheus stack)
- K8s deployments/services/ingress (managed by kubectl/CD pipeline)
- Node group scaling (scaled to 2 via AWS CLI, synced in variables.tf)

State file: local (`terraform.tfstate`) — no remote backend configured.

---

## Current Deployment State (as of Feb 9, 2026)

- **Cluster**: `bookstore-eks-EFruva57` — 2 nodes (t3.small SPOT)
- **App pods**: API and UI running in `bookstore` namespace
- **ALB**: `k8s-bookstor-bookstor-b584ea5605-1981577901.us-east-1.elb.amazonaws.com`
- **Monitoring**: Prometheus + Grafana running in `monitoring` namespace
- **CI/CD**: Both pipelines tested and working
- **Grafana access**: `kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring` → `admin` / `bookstore-admin`

---

## Bootstrap (Fresh Start)

After `terraform destroy` + `terraform apply`:
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Then manually:
1. Update GitHub secret `AWS_ROLE_ARN` with new value from `terraform output github_actions_role_arn`
2. Commit & push updated `cd.yaml` (bootstrap.sh updates the cluster name in it)

---

## Useful Commands

```bash
# Connect to cluster
aws eks update-kubeconfig --name bookstore-eks-EFruva57 --region us-east-1

# Check pods
kubectl get pods -n bookstore
kubectl get pods -n monitoring

# Check ALB URL
kubectl get ingress -n bookstore

# LB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20

# Grafana
kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Terraform outputs
cd terraform && terraform output
```
