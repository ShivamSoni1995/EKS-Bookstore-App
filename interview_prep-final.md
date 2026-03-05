# EKS Bookstore App — Interview Preparation Cheat Sheet
Repository: ShivamSoni1995/EKS-Bookstore-App | AWS Account: 342206309108 | Region: us-east-1

---

## QUICK REFERENCE

| Component       | Details                                                                 |
|-----------------|-------------------------------------------------------------------------|
| Backend         | Python 3.11, Flask 2.2.3 — file: api/main.py, FLASK_APP=main.py        |
| Frontend        | React 19, Node 20 — served by server.js using serve-handler             |
| Containers      | Docker multi-stage (UI), slim image (API)                               |
| Orchestration   | Amazon EKS 1.28, namespace: bookstore                                   |
| Infrastructure  | Terraform — AWS provider ~5.0, EKS module ~19.0, VPC module ~5.0        |
| CI/CD           | GitHub Actions with OIDC (no stored AWS keys)                           |
| Ingress         | AWS ALB via aws-load-balancer-controller                                |
| Monitoring      | kube-prometheus-stack (Prometheus + Grafana + Alertmanager)             |
| Cluster Name    | bookstore-eks-EFruva57 (random suffix — changes on each terraform apply)|
| Estimated Cost  | ~$30–40/month on SPOT t3.small nodes with no NAT gateway                |

---

## SECTION 1 — TERRAFORM INFRASTRUCTURE

Terraform provisions all AWS resources. State is stored locally (no remote backend configured).
A random suffix on the cluster name means it changes on every destroy/apply cycle.


### 1.1  Key Files

| File                              | Purpose                                                                 |
|-----------------------------------|-------------------------------------------------------------------------|
| terraform/main.tf                 | Providers (aws, kubernetes, helm), random cluster name suffix           |
| terraform/vpc.tf                  | VPC 10.0.0.0/16, 2 AZs, public subnets only, no NAT gateway            |
| terraform/eks-cluster.tf          | EKS 1.28, IRSA enabled, SPOT managed node group, aws-auth              |
| terraform/ecr.tf                  | bookstore-api & bookstore-ui repos; lifecycle: keep 5 images            |
| terraform/iam.tf                  | GitHub Actions OIDC provider + IAM role (no stored keys)               |
| terraform/lb-controller.tf        | IRSA role for the AWS Load Balancer Controller                          |
| terraform/lb-controller-policy.json | IAM policy v2.12.0 — includes DescribeListenerAttributes             |
| terraform/outputs.tf              | Exports cluster_name, ecr_urls, role_arns, region                      |
| terraform/variables.tf            | Defaults: t3.small, 2 SPOT nodes, us-east-1                            |


### 1.2  Architecture Decisions

- VPC uses public subnets only — eliminates ~$32/month NAT Gateway cost
- map_public_ip_on_launch = true required so SPOT nodes can reach ECR and the internet
- 2 Availability Zones instead of 3 — reduces subnet count and complexity
- SPOT instances (t3.small) — 60–70% cheaper than on-demand (~$8–10/mo for 2 nodes vs ~$60/mo)
- 2 nodes required because t3.small has an ENI limit of 11 pods — monitoring stack fills a whole node
- ECR lifecycle policy keeps only 5 images — minimises storage cost
- No EBS CSI driver installed — Prometheus uses emptyDir (data lost on pod restart, acceptable for demo)
- Local Terraform state — fine for a solo demo project; S3 + DynamoDB locking needed for teams


### 1.3  CRITICAL GOTCHA: manage_aws_auth_configmap

On the FIRST terraform apply, the aws-auth ConfigMap does not exist yet.
  Step 1: Set manage_aws_auth_configmap = false in eks-cluster.tf → terraform apply
  Step 2: Set manage_aws_auth_configmap = true → terraform apply again

Skipping this two-apply pattern causes Terraform to error out because it tries to
manage a ConfigMap that doesn't exist before the cluster is created.


### 1.4  Cost Breakdown

| Resource              | Cost                                      |
|-----------------------|-------------------------------------------|
| SPOT t3.small x2      | ~$8–10/month total (vs ~$60/mo on-demand) |
| No NAT Gateway        | Saves ~$32/month                          |
| ECR storage (5 images)| Minimal — <$1/month                       |
| ALB                   | ~$16–20/month (fixed + LCU charges)       |
| Estimated total       | ~$30–40/month = ~3 months on $120 credits |


### 1.5  What Terraform Does NOT Manage

- Helm releases — aws-load-balancer-controller and kube-prometheus-stack installed via bootstrap.sh
- K8s deployments/services/ingress — managed by kubectl through the CD pipeline
- Node scaling — scaled to 2 nodes via AWS CLI, then synced back into variables.tf


### 1.6  Interview Tips

✔ Explain the SPOT + public subnets trade-off: "I optimised for cost on a $120 credit budget.
  In production I'd use private subnets with NAT and reserved/on-demand nodes for critical workloads."

✔ Use the two-apply gotcha as a concrete debugging story — interviewers love real lessons learned.

✔ Address local state directly: "For a team environment I'd use an S3 backend with DynamoDB
  locking for collaboration and a full audit trail."

✔ The random cluster name suffix is intentional — it forces reading terraform output rather
  than hardcoding names anywhere in scripts or pipelines.

---

## SECTION 2 — GITHUB ACTIONS CI/CD PIPELINES

Two pipelines: CI on develop (test + build), CD on main (build + deploy).
OIDC authentication means no AWS credentials are ever stored as GitHub Secrets.


### 2.1  Branch Strategy

| Branch    | Trigger | What happens                                              |
|-----------|---------|-----------------------------------------------------------|
| develop   | Push    | CI: run tests → build Docker images → push to ECR (SHA tag) |
| main      | Push/Merge | CD: build + push (SHA, latest, production tags) → deploy to EKS |

Workflow: push to develop → CI passes → merge to main → CD deploys automatically.

Required GitHub Secret:
  AWS_ROLE_ARN = arn:aws:iam::342206309108:role/github-actions-bookstore-role
  (This ARN changes every time the cluster is recreated via terraform.)


### 2.2  CI Pipeline (.github/workflows/ci.yaml)

Jobs (all triggered on push to develop):

  1. test-backend
     - pip install -r requirements.txt
     - pytest api/test_main.py

  2. test-frontend
     - npm install
     - jest smoke test (simplified — cannot import react-router-dom in CI env)

  3. build-and-push  (depends on BOTH test jobs passing)
     - docker build for api and ui
     - Push to ECR tagged with $GITHUB_SHA

Authentication: OIDC via aws-actions/configure-aws-credentials — no stored access keys.


### 2.3  CD Pipeline (.github/workflows/cd.yaml)

Single job triggered on push to main:

  1. Build & push images with 3 tags: $GITHUB_SHA, latest, production
  2. aws eks update-kubeconfig to connect kubectl to the cluster
  3. sed replaces image tags in k8s manifests with the new SHA
  4. kubectl apply -f k8s/ (namespace, deployments, services, ingress)
  5. kubectl rollout status — waits for rollout to complete before succeeding

The sed pattern must match actual ECR URLs exactly:
  Pattern: 342206309108.dkr.ecr.us-east-1.amazonaws.com/bookstore-api:[a-zA-Z0-9]*
  (Using ${AWS_ACCOUNT_ID} placeholders will break the sed replacement.)


### 2.4  CRITICAL GOTCHA: Frontend Test Import

The full App.test.js imports react-router-dom which fails in the CI environment.
Fix: simplified the test to a smoke test with no router dependency.
Lesson: always check that test dependencies are available in the CI runner.


### 2.5  Image Tagging Strategy

| Tag          | Purpose                                              |
|--------------|------------------------------------------------------|
| $GITHUB_SHA  | Unique, immutable — used in K8s manifests            |
| latest       | Convenience — for manual pulls / local testing       |
| production   | Semantic marker for the most recent production build |


### 2.6  Interview Tips

✔ Emphasise OIDC: "No long-lived credentials are stored anywhere. GitHub assumes an IAM role
  using a short-lived token scoped to this specific repo and branch."

✔ Explain the three-tag strategy: "SHA gives immutability and traceability; latest and
  production give humans a convenient reference without digging through SHAs."

✔ The sed gotcha is a strong example: "I learned to always use literal values in manifests
  and match the sed regex to the actual URL, not a template variable."

✔ Mention that CI and CD are intentionally separate: "Keeps the fast feedback loop (tests)
  decoupled from the slower deployment concern."

---

## SECTION 3 — AMAZON EKS / KUBERNETES DEPLOYMENT

EKS 1.28 cluster running 2 SPOT t3.small nodes. All app resources live in the
'bookstore' namespace. Ingress is handled by an internet-facing AWS ALB.


### 3.1  Key Manifest Files (k8s/)

| File                    | What it does                                              |
|-------------------------|-----------------------------------------------------------|
| namespace.yaml          | Creates the 'bookstore' namespace                         |
| api-deployment.yaml     | 1 replica, ClusterIP service on port 5000                 |
| ui-deployment.yaml      | 1 replica, ClusterIP service on port 3000                 |
| ingress.yaml            | ALB ingress: /api/* → api:80, /* → ui:80                  |
| prometheus-values.yaml  | Helm values: resource limits, emptyDir, no PVC            |


### 3.2  Networking & Ingress

- ingressClassName: alb — tells the LB controller to create an internet-facing ALB
- The ALB routes /api/* to the API service and /* to the UI service
- UI's server.js proxies /api/ calls to http://api (the K8s ClusterIP service name)
  This means the browser hits the ALB → UI pod → server.js proxies to API pod
- No custom domain configured — access via raw ALB DNS name

Current ALB DNS:
  k8s-bookstor-bookstor-b584ea5605-1981577901.us-east-1.elb.amazonaws.com


### 3.3  SPOT Node Gotcha: Pod Limit

t3.small supports a maximum of 11 pods per node (ENI limit).
The monitoring stack (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics)
consumes roughly one full node. This is why 2 nodes are required even though the app itself
(API pod + UI pod) is tiny.


### 3.4  aws-load-balancer-controller

- Installed via Helm (NOT managed by Terraform)
- Uses IRSA (IAM Roles for Service Accounts) — pod-level AWS credentials, no node-level keys
- Requires IAM policy v2.12.0 (v2.7.1 was missing ec2:GetSecurityGroupsForVpc
  and elasticloadbalancing:DescribeListenerAttributes — caused controller to fail)
- Helm release: aws-load-balancer-controller in kube-system namespace


### 3.5  Docker Builds

API (api/Dockerfile):
  - Base: python:3.11-slim
  - CRITICAL: ENV FLASK_APP=main.py (file is main.py, NOT app.py)
  - pip install flask flask-cors psycopg

UI (ui/Dockerfile):
  - Multi-stage: node:20-alpine for build → production image
  - Stage 1: npm install && npm run build (produces static React bundle)
  - Stage 2: copies bundle into production image, runs server.js
  - server.js uses serve-handler for static files + http-proxy-middleware for /api/ proxy


### 3.6  Useful kubectl Commands

  # Connect to cluster
  aws eks update-kubeconfig --name bookstore-eks-EFruva57 --region us-east-1

  # Check pods
  kubectl get pods -n bookstore
  kubectl get pods -n monitoring

  # View ALB URL
  kubectl get ingress -n bookstore

  # View pod logs
  kubectl logs -n bookstore deployment/api
  kubectl logs -n bookstore deployment/ui

  # LB controller logs
  kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20


### 3.7  Interview Tips

✔ Explain IRSA: "Instead of giving EC2 nodes a broad IAM role, IRSA scopes credentials to
  a specific service account. Each workload only gets the permissions it needs."

✔ The LB controller IAM policy version is a great gotcha story: "The default policy from the
  docs was missing two actions. I tracked it down in controller logs and fixed it by upgrading
  to the v2.12.0 policy."

✔ On the proxy pattern: "The React app doesn't know the API URL at runtime — the server.js
  proxy translates /api/ calls to the Kubernetes internal service name http://api.
  This keeps the frontend config environment-agnostic."

✔ On single replicas: "For a demo project 1 replica is fine and keeps cost down. In production
  I'd set replicas: 2+ with pod disruption budgets and a HorizontalPodAutoscaler."

---

## SECTION 4 — MONITORING WITH KUBE-PROMETHEUS-STACK

Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics
all deployed via a single Helm chart into the 'monitoring' namespace.


### 4.1  Installation

Installed via Helm (not Terraform) as part of bootstrap.sh:

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring \
    -f k8s/prometheus-values.yaml

Values file (k8s/prometheus-values.yaml) key settings:
  - Reduced resource requests/limits to fit on t3.small nodes
  - storageSpec: {} — uses emptyDir (no PersistentVolumeClaim)
  - No EBS CSI driver installed, so PVCs would get stuck in Pending without this setting


### 4.2  Accessing Grafana

  kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring
  → http://localhost:3001
  Login: admin / bookstore-admin


### 4.3  Accessing Prometheus

  kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
  → http://localhost:9090


### 4.4  Useful PromQL Queries

  # Pod CPU usage
  sum(rate(container_cpu_usage_seconds_total{namespace="bookstore"}[5m])) by (pod)

  # Pod memory usage
  sum(container_memory_working_set_bytes{namespace="bookstore"}) by (pod)

  # HTTP request rate (if Flask is instrumented)
  rate(flask_http_request_total[5m])

  # Node count
  count(kube_node_info)


### 4.5  Resource & Design Decisions

- emptyDir for Prometheus storage: no persistent data — monitoring data resets on pod restart.
  Acceptable for a demo; in production use PersistentVolumeClaims via EBS CSI driver.
- Resource limits tightened to fit the full stack on 2x t3.small SPOT nodes.
- Alertmanager included in the chart but no Slack/email alerts configured (future enhancement).
- kube-state-metrics and node-exporter deployed automatically by the chart —
  provides cluster-level and node-level metrics out of the box.


### 4.6  Interview Tips

✔ "I chose kube-prometheus-stack because it bundles everything — Prometheus, Grafana,
  Alertmanager, and exporters — in a single Helm release. Much faster than wiring them
  individually for a demo project."

✔ On the emptyDir decision: "I made a conscious trade-off: saving ~$0.50/month on EBS
  and avoiding the EBS CSI driver setup, at the cost of losing metrics on pod restart.
  For production, I'd install the EBS CSI driver and use a PVC."

✔ "The hardest part was fitting the monitoring stack on t3.small nodes. I had to tune
  resource requests in prometheus-values.yaml and scale from 1 to 2 nodes because of
  the ENI pod limit."

✔ If asked about alerts: "Alertmanager is deployed but I haven't wired up a notification
  channel yet. I'd add a Slack webhook and PrometheusRule CRDs to alert on pod crashes,
  high error rates, and node memory pressure."

---

## SECTION 5 — OTHER KEY DETAILS

### 5.1  Flask API Endpoints

| Method | Endpoint                       | Description              |
|--------|--------------------------------|--------------------------|
| GET    | /api/health                    | Health check             |
| GET    | /api/products                  | List all products        |
| GET    | /api/products/<id>             | Get product by ID        |
| GET    | /api/categories                | List all categories      |
| GET    | /api/categories/<id>/products  | Products by category     |


### 5.2  React Frontend Routing

- Uses BrowserRouter (react-router-dom v7) in App.js
- Pages: Home, ProductList, ProductDetail, Cart
- Components: Navbar, Footer, Hero
- API calls go to /api/ — proxied by server.js to the Kubernetes API service


### 5.3  bootstrap.sh (One-Command Post-Terraform Deployment)

After terraform apply, bootstrap.sh automates everything else:
  1. Reads terraform outputs (cluster name, ECR URLs, role ARNs)
  2. Runs aws eks update-kubeconfig
  3. Builds and pushes Docker images to ECR
  4. kubectl apply -f k8s/ (namespace, deployments, services, ingress)
  5. Installs aws-load-balancer-controller via Helm
  6. Installs kube-prometheus-stack via Helm
  7. Updates the EKS_CLUSTER_NAME in .github/workflows/cd.yaml

After bootstrap.sh, two manual steps remain:
  - Update the AWS_ROLE_ARN GitHub secret with the new IAM role ARN
  - Push a commit to trigger the first CD pipeline run


### 5.4  Tear Down Order (Important)

  1. helm uninstall prometheus -n monitoring
  2. helm uninstall aws-load-balancer-controller -n kube-system
  3. kubectl delete -f k8s/
  4. cd terraform && terraform destroy

Helm releases must be removed BEFORE terraform destroy — otherwise the ALB and
security groups created by the controller will block VPC deletion.


### 5.5  Full Bug Fix History (Great Interview Stories)

1. manage_aws_auth_configmap: false on first apply, true on second.
   (ConfigMap doesn't exist before the cluster is created.)

2. map_public_ip_on_launch = true in vpc.tf — without this, SPOT nodes
   on public subnets cannot reach the internet or ECR.

3. FLASK_APP=main.py in the API Dockerfile — the file is main.py, not app.py.
   Flask couldn't find the app until this was set explicitly.

4. K8s manifest image URLs must use literal ECR URLs, not ${AWS_ACCOUNT_ID}
   placeholders — the CD pipeline sed command must match the exact URL pattern.

5. LB controller IAM policy v2.7.1 was missing ec2:GetSecurityGroupsForVpc and
   elasticloadbalancing:DescribeListenerAttributes — upgraded to v2.12.0 policy.

6. t3.small ENI pod limit of 11 pods per node — had to scale from 1 to 2 nodes
   once the monitoring stack was added.

7. EBS CSI driver not installed by default — set Prometheus storageSpec: {} to
   use emptyDir and avoid PVCs getting stuck in Pending state.

8. Frontend jest test imported react-router-dom which failed in CI — simplified
   to a smoke test with no router dependency.

9. CD pipeline sed pattern must match the actual ECR URL format exactly —
   using variable placeholders silently failed to update the image tag.

---

## SECTION 6 — QUICK-FIRE ANSWERS

Q: Why EKS instead of ECS or Lambda?
A: EKS gives full Kubernetes compatibility — portable across clouds, richer ecosystem
   (Helm, Prometheus operator, etc.), and demonstrates real-world K8s skills.

Q: Why SPOT instances?
A: 60–70% cost reduction. For a stateless, fault-tolerant demo app, SPOT interruptions
   are acceptable. In production, use SPOT for non-critical workloads and on-demand for
   API/DB pods that need stability.

Q: Why no NAT gateway?
A: Costs ~$32/month — nearly the same as the nodes themselves. Public subnets with
   map_public_ip_on_launch = true achieve the same connectivity for a demo project.

Q: Why OIDC for GitHub Actions?
A: No long-lived credentials stored in GitHub Secrets. Short-lived tokens are issued
   per-workflow-run and scoped to a specific repo/branch. Much more secure than
   static access keys.

Q: How does the frontend talk to the backend?
A: Browser → ALB → UI pod (server.js) → proxy → API pod (Flask) via K8s internal DNS.
   The React app uses relative /api/ paths; server.js translates them to http://api
   which resolves to the API ClusterIP service inside the cluster.

Q: What would you improve for production?
A:
  - Remote Terraform state (S3 + DynamoDB)
  - Private subnets + NAT gateway
  - Multiple replicas + HPA + PodDisruptionBudgets
  - RDS database (currently data is hardcoded in Flask)
  - Custom domain + ACM TLS certificate on the ALB
  - EBS CSI driver + persistent storage for Prometheus
  - Slack/PagerDuty alerts via Alertmanager
  - Secrets manager for credentials (no plaintext in ConfigMaps)

---

End of Cheat Sheet
