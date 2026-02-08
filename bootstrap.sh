#!/bin/bash
# bootstrap.sh - Automates full deployment after terraform apply
# Usage: ./bootstrap.sh
# Prerequisites: AWS CLI configured, kubectl, helm, docker installed

set -e

echo "========================================="
echo "  Bookstore App - Bootstrap Deployment"
echo "========================================="

# ─── 1. Get values from Terraform output ───
echo ""
echo "[1/9] Reading Terraform outputs..."
CLUSTER_NAME=$(terraform -chdir=terraform output -raw cluster_name)
ECR_API_URL=$(terraform -chdir=terraform output -raw ecr_api_repository_url)
ECR_UI_URL=$(terraform -chdir=terraform output -raw ecr_ui_repository_url)
LB_ROLE_ARN=$(terraform -chdir=terraform output -raw lb_controller_role_arn)
GH_ROLE_ARN=$(terraform -chdir=terraform output -raw github_actions_role_arn)
REGION=$(terraform -chdir=terraform output -raw region)
ACCOUNT_ID=$(echo "$ECR_API_URL" | cut -d'.' -f1)

echo "  Cluster:       $CLUSTER_NAME"
echo "  Region:        $REGION"
echo "  Account ID:    $ACCOUNT_ID"
echo "  ECR API:       $ECR_API_URL"
echo "  ECR UI:        $ECR_UI_URL"
echo "  LB Role ARN:   $LB_ROLE_ARN"
echo "  GH Role ARN:   $GH_ROLE_ARN"

# ─── 2. Connect kubectl ───
echo ""
echo "[2/9] Configuring kubectl..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
echo "  Connected to cluster: $CLUSTER_NAME"

# ─── 3. Build & push Docker images ───
echo ""
echo "[3/9] Logging into ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

echo ""
echo "[4/9] Building and pushing API image..."
docker build -t "$ECR_API_URL:latest" -t "$ECR_API_URL:production" api/
docker push "$ECR_API_URL:latest"
docker push "$ECR_API_URL:production"

echo ""
echo "[5/9] Building and pushing UI image..."
docker build -t "$ECR_UI_URL:latest" -t "$ECR_UI_URL:production" ui/
docker push "$ECR_UI_URL:latest"
docker push "$ECR_UI_URL:production"

# ─── 4. Update K8s manifests with correct ECR URLs ───
echo ""
echo "[6/9] Updating K8s manifests with ECR URLs..."
sed -i "s|image:.*bookstore-api.*|image: $ECR_API_URL:latest|" k8s/api-deployment.yaml
sed -i "s|image:.*bookstore-ui.*|image: $ECR_UI_URL:latest|" k8s/ui-deployment.yaml
echo "  Updated api-deployment.yaml"
echo "  Updated ui-deployment.yaml"

# ─── 5. Deploy app to EKS ───
echo ""
echo "[7/9] Deploying application to EKS..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/api-deployment.yaml
kubectl apply -f k8s/ui-deployment.yaml
echo "  Waiting for pods to be ready..."
kubectl rollout status deployment/api -n bookstore --timeout=120s
kubectl rollout status deployment/ui -n bookstore --timeout=120s
echo "  All pods running!"

# ─── 6. Install AWS Load Balancer Controller ───
echo ""
echo "[8/9] Installing AWS Load Balancer Controller..."
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

# Check if already installed
if helm list -n kube-system | grep -q aws-load-balancer-controller; then
  echo "  LB Controller already installed, upgrading..."
  helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set "serviceAccount.annotations.eks\.amazonaws\.io/role-arn=$LB_ROLE_ARN"
else
  helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$CLUSTER_NAME" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set "serviceAccount.annotations.eks\.amazonaws\.io/role-arn=$LB_ROLE_ARN"
fi

# Apply Ingress
kubectl apply -f k8s/ingress.yaml
echo "  LB Controller and Ingress deployed!"

# ─── 7. Scale nodes & install monitoring ───
echo ""
echo "[9/9] Setting up monitoring..."

# Scale node group to 2 for monitoring pods
NODEGROUP=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --region "$REGION" --query 'nodegroups[0]' --output text)
echo "  Scaling node group $NODEGROUP to 2 nodes..."
aws eks update-nodegroup-config \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$NODEGROUP" \
  --scaling-config desiredSize=2,minSize=1,maxSize=2 \
  --region "$REGION"

# Wait for second node
echo "  Waiting for second node to join (this may take ~2 min)..."
while [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -lt 2 ]; do
  sleep 10
  echo "    Nodes ready: $(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')/2"
done
echo "  Both nodes ready!"

# Install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

if helm list -n monitoring | grep -q prometheus; then
  echo "  Prometheus stack already installed, upgrading..."
  helm upgrade prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring -f k8s/prometheus-values.yaml
else
  helm install prometheus prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    -f k8s/prometheus-values.yaml --wait --timeout 5m
fi
echo "  Monitoring stack deployed!"

# ─── 8. Update CD pipeline ───
echo ""
echo "Updating CD pipeline with new cluster name..."
sed -i "s|EKS_CLUSTER_NAME:.*|EKS_CLUSTER_NAME: $CLUSTER_NAME|" .github/workflows/cd.yaml
echo "  Updated cd.yaml"

# ─── Summary ───
echo ""
echo "========================================="
echo "  Deployment Complete!"
echo "========================================="
echo ""
echo "  Cluster:    $CLUSTER_NAME"
echo "  Region:     $REGION"
echo ""

# Wait for ALB
echo "  Waiting for ALB address..."
for i in $(seq 1 30); do
  ALB_URL=$(kubectl get ingress bookstore-ingress -n bookstore -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [ -n "$ALB_URL" ]; then
    break
  fi
  sleep 10
done

if [ -n "$ALB_URL" ]; then
  echo ""
  echo "  UI:   http://$ALB_URL/"
  echo "  API:  http://$ALB_URL/api/health"
else
  echo "  ALB not ready yet. Check with:"
  echo "    kubectl get ingress -n bookstore"
fi

echo ""
echo "  Grafana:  kubectl port-forward svc/prometheus-grafana 3001:80 -n monitoring"
echo "            http://localhost:3001  (admin / bookstore-admin)"
echo ""
echo "  Prometheus: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
echo "              http://localhost:9090"
echo ""
echo "  ⚠️  MANUAL STEPS REMAINING:"
echo "  1. Update GitHub secret AWS_ROLE_ARN to: $GH_ROLE_ARN"
echo "  2. Commit and push cd.yaml changes"
echo ""
