#!/bin/bash
# deploy.sh - Deploy the BookStore application

set -e

echo "========================================"
echo "Deploying BookStore Application"
echo "========================================"
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured. Please configure kubectl first."
    exit 1
fi

# Deploy application
echo "Deploying application resources..."
kubectl apply -f ../kubernetes/bookstore-deployment.yml

echo ""
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/bookapp-ui -n bookstore
kubectl wait --for=condition=available --timeout=300s deployment/bookapp-api -n bookstore

echo ""
echo "✓ Deployments are ready!"

# Wait for ingress
echo ""
echo "Waiting for ingress to be ready (this may take 2-3 minutes)..."
sleep 30

# Get ingress URL
ALB_DNS=$(kubectl get ingress bookstore-ingress -n bookstore -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$ALB_DNS" ]; then
    echo "⚠ Ingress is still being created. Please wait a few minutes and run:"
    echo "kubectl get ingress bookstore-ingress -n bookstore"
else
    echo ""
    echo "========================================"
    echo "✓ Deployment Successful!"
    echo "========================================"
    echo ""
    echo "Your application is available at:"
    echo "UI:  http://$ALB_DNS/"
    echo "API: http://$ALB_DNS/api/"
    echo ""
fi

echo "Check deployment status:"
echo "kubectl get all -n bookstore"
echo ""
echo "View logs:"
echo "kubectl logs -f deployment/bookapp-ui -n bookstore"
echo "kubectl logs -f deployment/bookapp-api -n bookstore"
