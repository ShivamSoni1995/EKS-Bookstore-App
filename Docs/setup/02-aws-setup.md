# AWS Cloud Setup

This guide walks through provisioning the infrastructure and deploying the app to EKS from scratch.

---

## Step 1 — Provision Infrastructure with Terraform

### Why two applies?

The EKS `aws-auth` ConfigMap (which maps IAM roles to Kubernetes RBAC) does not exist before the cluster is created. Terraform cannot manage it on the first apply. So the process is:

1. First apply — creates everything **except** aws-auth management
2. Second apply — Terraform takes over aws-auth and maps the GitHub Actions role to `system:masters`

### First Apply

Edit `terraform/eks-cluster.tf` and set:
```hcl
manage_aws_auth_configmap = false
```

Then:
```bash
cd terraform
terraform init
terraform apply
```

### Second Apply

Edit `terraform/eks-cluster.tf` and set:
```hcl
manage_aws_auth_configmap = true
```

Then:
```bash
terraform apply
```

---

## Step 2 — Add GitHub Secret

After Terraform completes, copy the IAM role ARN:
```bash
cd terraform
terraform output github_actions_role_arn
```

Go to your GitHub repository → **Settings → Secrets and variables → Actions → New repository secret**:

| Name | Value |
|------|-------|
| `AWS_ROLE_ARN` | The ARN from `terraform output` above |

> **Important**: This ARN changes every time you run `terraform destroy` + `terraform apply` because the cluster name includes a random suffix. You must update this secret each time.

---

## Step 3 — Run bootstrap.sh

`bootstrap.sh` automates everything after Terraform:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

What it does, in order:
1. Reads cluster name, ECR URLs, and role ARNs from `terraform output`
2. Runs `aws eks update-kubeconfig` to configure kubectl
3. Authenticates Docker to ECR
4. Builds and pushes `bookstore-api` and `bookstore-ui` Docker images
5. Applies all Kubernetes manifests (`namespace`, `api-deployment`, `ui-deployment`, `ingress`)
6. Installs **AWS Load Balancer Controller** via Helm (uses IRSA role from Terraform)
7. Installs **kube-prometheus-stack** via Helm (Prometheus + Grafana + Alertmanager)
8. Updates `cd.yaml` with the current cluster name
9. Deploys the ServiceMonitor for Flask metrics scraping

> If any step fails, the script exits. Re-run after fixing the issue — all steps are idempotent.

---

## Step 4 — Access the Application

The ALB is provisioned by the Load Balancer Controller after the ingress is applied. It takes 2–3 minutes.

```bash
# Watch until ADDRESS is populated
kubectl get ingress -n bookstore --watch

# Once ready, open in browser:
# http://<ALB_DNS_NAME>/
```

---

## Step 5 — Update cd.yaml (if cluster name changed)

If you destroyed and recreated the cluster, the cluster name will have changed. Bootstrap updates `cd.yaml` automatically, but verify:

```bash
grep EKS_CLUSTER_NAME .github/workflows/cd.yaml
```

If it doesn't match `terraform output cluster_name`, update it manually.

---

## Post-Setup Verification

```bash
# All pods running?
kubectl get pods -n bookstore
kubectl get pods -n monitoring

# Ingress has an ALB address?
kubectl get ingress -n bookstore

# LB controller healthy?
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller --tail=10
```

---

## Useful Terraform Outputs

```bash
cd terraform

terraform output cluster_name
terraform output ecr_api_url
terraform output ecr_ui_url
terraform output github_actions_role_arn
terraform output lb_controller_role_arn
```
