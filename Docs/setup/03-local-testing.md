# Local Testing with k3d

Run the full stack locally — Flask API, React UI, Prometheus, and Grafana — using [k3d](https://k3d.io). No AWS account required.

---

## Prerequisites

- Docker
- k3d v5+
- kubectl
- Helm v3+

---

## Important: Image Names for Local Use

The Kubernetes deployment manifests reference ECR image URLs (e.g. `342206309108.dkr.ecr.us-east-1.amazonaws.com/bookstore-api:latest`). For local use, you build and import images with simple names (`bookstore-api:latest`), and the `imagePullPolicy: IfNotPresent` setting ensures K8s uses the locally imported image — **but only if the image name in the manifest matches exactly**.

If you have not modified the manifests, you need to patch the image references for local use:
```bash
# Temporary patch for local testing (do not commit)
kubectl set image deployment/api api=bookstore-api:latest -n bookstore
kubectl set image deployment/ui ui=bookstore-ui:latest -n bookstore
```

Or edit `k8s/api-deployment.yaml` and `k8s/ui-deployment.yaml` to use `bookstore-api:latest` and `bookstore-ui:latest` before applying.

---

## Step 1 — Create the k3d Cluster

Create the cluster with port 9080 mapped to the load balancer and Traefik disabled (NGINX Ingress is used instead):

```bash
k3d cluster create bookstore \
  --port "9080:80@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0"
```

> **Port note**: Port 9080 is used instead of 8080 to avoid conflicts with other local services (e.g. Jenkins). Change it if needed — just update the `curl` commands below accordingly.

Install the NGINX Ingress Controller:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

---

## Step 2 — Build and Import Docker Images

```bash
# Build both images
docker build -t bookstore-api:latest ./api
docker build -t bookstore-ui:latest ./ui

# Import into k3d containerd (no registry needed)
k3d image import bookstore-api:latest bookstore-ui:latest -c bookstore
```

The import copies images directly into k3d's containerd runtime — no ECR, no registry pull.

---

## Step 3 — Deploy the Application

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/ui-deployment.yaml

# Use the NGINX ingress (NOT ingress.yaml which has ALB annotations)
kubectl apply -f k8s/ingress-local.yaml

# Wait for pods to be ready
kubectl rollout status deployment/api -n bookstore
kubectl rollout status deployment/ui -n bookstore
```

> **Do not apply `k8s/ingress.yaml` locally** — it uses AWS ALB annotations (`ingressClassName: alb`) that only work with the AWS Load Balancer Controller on EKS.

---

## Step 4 — Access the Application

```bash
# API health check
curl http://localhost:9080/api/health
# → {"status":"healthy"}

# Products and categories
curl http://localhost:9080/api/products/featured
curl http://localhost:9080/api/categories

# UI — open in browser
# http://localhost:9080
```

---

## Step 5 — Install Monitoring Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f k8s/prometheus-values.yaml

# Deploy the ServiceMonitor for Flask app metrics
kubectl apply -f k8s/api-metrics-servicemonitor.yaml
```

Wait for all monitoring pods to be ready:
```bash
kubectl get pods -n monitoring --watch
# All should show Running. Grafana may take 60s (3/3 containers).
```

---

## Step 6 — Access Monitoring Dashboards

```bash
# Grafana
kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring &
# → http://localhost:3001
# Login: admin / bookstore-admin

# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
# → http://localhost:9090
```

---

## Step 7 — Generate Traffic and Verify Metrics

```bash
# Generate API traffic (via ingress)
for i in $(seq 1 20); do
  curl -s http://localhost:9080/api/health > /dev/null
  curl -s http://localhost:9080/api/products/featured > /dev/null
  curl -s http://localhost:9080/api/categories > /dev/null
done

# Check /metrics directly (port-forward needed — not exposed via ingress)
kubectl port-forward svc/api 5000:80 -n bookstore &
curl http://localhost:5000/metrics | grep flask_http_request_total
```

Open Prometheus at http://localhost:9090 and run:
```promql
sum(flask_http_request_total)
```

Verify the ServiceMonitor target is being scraped:
- Go to http://localhost:9090/targets
- Look for `serviceMonitor/bookstore/bookstore-api-metrics/0` → Health: **up**

---

## Step 8 — Tear Down

```bash
k3d cluster delete bookstore
```

This removes the cluster and all resources. Docker images remain in your local Docker daemon.

---

## Troubleshooting

**Pods stuck in `ImagePullBackOff`**
The image name in the manifest doesn't match what was imported. See the "Important: Image Names" note at the top of this guide.

**`localhost:9080` returns unexpected content (e.g. Jenkins)**
Another service is using port 9080. Delete the cluster and recreate with a different port mapping, e.g. `--port "8088:80@loadbalancer"`.

**ServiceMonitor shows 0 active targets**
Two things must be correct:
1. The `api` Service must have label `app: api` — check with `kubectl get svc api -n bookstore --show-labels`
2. The containerPort in `api-deployment.yaml` must have `name: http`

See [Docs/Monitoring.txt](../Monitoring.txt) for full troubleshooting.
