# CI/CD Pipeline

This project uses **GitHub Actions** with **OIDC authentication** — no AWS access keys are stored as GitHub secrets.

---

## Branching Strategy

```
feature/my-change
       │
       ▼ (pull request)
   develop  ──────► CI pipeline (test + build + push to ECR)
       │
       ▼ (pull request or direct merge)
     main   ──────► CD pipeline (build + push + deploy to EKS)
```

| Branch | Usage | Pipeline triggered |
|--------|-------|--------------------|
| `feature/*` | Day-to-day development | None (push only) |
| `develop` | Integration branch; all PRs merge here first | **CI** — tests, build, push |
| `main` | Production branch; only merge from develop | **CD** — build, push, deploy |

**Workflow for a change:**
1. Create a feature branch from `develop`
2. Push commits — no pipeline runs
3. Open a PR to `develop` → CI runs on merge
4. CI must pass before merging to `main`
5. Merge to `main` → CD deploys to EKS automatically

---

## OIDC Authentication (No Stored Keys)

Both pipelines use the `aws-actions/configure-aws-credentials` action with OIDC:

```yaml
- uses: aws-actions/configure-aws-credentials@v2
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: us-east-1
```

**How it works:**
1. GitHub generates a short-lived OIDC JWT token for the workflow run
2. AWS validates the token against the OIDC provider (`token.actions.githubusercontent.com`)
3. If the `sub` claim matches `repo:ShivamSoni1995/EKS-Bookstore-App:*`, AWS issues temporary credentials
4. Credentials expire after 1 hour — no rotation needed, no key leakage risk

**First-time setup:** The OIDC provider and IAM role are created by Terraform (`terraform/iam.tf`). After `terraform apply`, the role ARN must be manually added to GitHub Secrets as `AWS_ROLE_ARN`.

---

## CI Pipeline (`.github/workflows/ci.yaml`)

**Trigger:** Push to `develop`

```
Push to develop
  ├─► Job: test-backend
  │     pip install -r api/requirements.txt
  │     pytest api/test_main.py
  │
  ├─► Job: test-frontend
  │     npm install (in ui/)
  │     jest (smoke test — App renders without crashing)
  │
  └─► Job: build-and-push  [runs only if both tests pass]
        aws-actions/configure-aws-credentials (OIDC)
        aws ecr get-login-password | docker login
        docker build + push bookstore-api:$GITHUB_SHA
        docker build + push bookstore-ui:$GITHUB_SHA
```

The SHA tag means every commit produces a uniquely tagged image, making rollbacks trivial.

---

## CD Pipeline (`.github/workflows/cd.yaml`)

**Trigger:** Push to `main`

```
Push to main
  └─► Job: build-and-deploy
        1. aws-actions/configure-aws-credentials (OIDC)
        2. aws ecr get-login-password | docker login
        3. docker build + push with 3 tags:
             bookstore-api:$GITHUB_SHA
             bookstore-api:latest
             bookstore-api:production
           (same for bookstore-ui)
        4. aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
        5. sed replaces image tags in manifests ──► see below
        6. kubectl apply:
             k8s/namespace.yaml
             k8s/api-deployment.yaml
             k8s/ui-deployment.yaml
             k8s/ingress.yaml
             k8s/api-metrics-servicemonitor.yaml
        7. kubectl rollout status deployment/api -n bookstore
           kubectl rollout status deployment/ui -n bookstore
           (pipeline waits here — exits non-zero if rollout fails)
```

### What the `sed` command does

The K8s manifests in the repo contain placeholder image URLs with a `:latest` tag. The CD pipeline replaces them with the exact commit SHA before applying:

```bash
sed -i "s|bookstore-api:[a-zA-Z0-9]*|bookstore-api:$GITHUB_SHA|g" k8s/api-deployment.yaml
sed -i "s|bookstore-ui:[a-zA-Z0-9]*|bookstore-ui:$GITHUB_SHA|g" k8s/ui-deployment.yaml
```

This ensures EKS always pulls the exact image built from the current commit — not a cached `:latest`.

### Rolling Update Behaviour

When `kubectl apply` updates the Deployment with a new image tag, Kubernetes performs a **rolling update**:
1. New pod is created with the new image (pulled from ECR)
2. Readiness probe must pass before old pod is terminated
3. Old pod is removed
4. Zero downtime (1 replica — brief overlap during transition)

---

## Required GitHub Secret

| Secret | Value | Where to get it |
|--------|-------|-----------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::<account>:role/github-actions-bookstore-role` | `cd terraform && terraform output github_actions_role_arn` |

> This is the **only** secret. No `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`.

---

## IAM Permissions Granted to the Pipeline

The pipeline role can only do:
- **ECR**: push/pull images to the two specific repositories
- **EKS**: `DescribeCluster` + `ListClusters` (to fetch kubeconfig)
- **Kubernetes RBAC**: `system:masters` (full cluster admin — mapped via aws-auth ConfigMap)

See [Roles-Policies.txt](Roles-Policies.txt) for the full policy breakdown.
