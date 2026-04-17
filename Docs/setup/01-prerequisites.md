# Prerequisites

Before setting up this project — locally or on AWS — make sure the following are in place.

---

## Required Tools

| Tool | Version | Install |
|------|---------|---------|
| **AWS CLI** | v2 | [docs.aws.amazon.com/cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| **Terraform** | >= 1.0 | [developer.hashicorp.com/terraform](https://developer.hashicorp.com/terraform/install) |
| **kubectl** | v1.28+ | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | v3+ | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| **Docker** | latest | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| **Node.js** | 18+ | [nodejs.org](https://nodejs.org/) — only needed for local UI development |
| **Python** | 3.11+ | [python.org](https://python.org/) — only needed for local API development |
| **k3d** | v5+ | [k3d.io/#installation](https://k3d.io/#installation) — only needed for local k3d testing |

Verify everything is installed:
```bash
aws --version
terraform -version
kubectl version --client
helm version --short
docker --version
```

---

## AWS Account Requirements

### IAM Permissions for the Human Running Terraform

The user or role running `terraform apply` needs **AdministratorAccess** or at minimum these managed policies:

- `AmazonEKSClusterPolicy`
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2FullAccess`
- `IAMFullAccess`
- `AmazonECRFullAccess`
- `AmazonVPCFullAccess`

> **Simplest option for a personal project**: attach `AdministratorAccess` to your IAM user. Terraform creates many interdependent resources (VPC, EKS, ECR, IAM roles, OIDC provider) and a narrow policy is tedious to maintain.

### AWS CLI Configuration

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)

# Verify
aws sts get-caller-identity
```

---

## GitHub Repository Setup

1. Fork or clone this repository to your GitHub account.
2. The CI/CD pipelines use **OIDC authentication** — no AWS access keys are stored in GitHub.
3. One secret needs to be added after Terraform runs (see [02-aws-setup.md](02-aws-setup.md)).

---

## Local Development Only (no AWS needed)

If you only want to test locally with k3d, you need:

- Docker
- k3d v5+
- kubectl
- Helm v3+

See [03-local-testing.md](03-local-testing.md) for the full guide.
