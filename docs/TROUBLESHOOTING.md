# Troubleshooting Guide

## Common Issues

### 1. Ingress Not Getting ALB DNS

**Symptoms**: No hostname in ingress status after 5+ minutes

**Solutions**:
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Verify controller is running
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check service account
kubectl get serviceaccount aws-load-balancer-controller -n kube-system -o yaml
```

### 2. Pods Not Starting

**Symptoms**: Pods stuck in Pending or CrashLoopBackOff

**Solutions**:
```bash
# Check pod details
kubectl describe pod <pod-name> -n bookstore

# Check node resources
kubectl describe nodes

# View pod logs
kubectl logs <pod-name> -n bookstore

# Check events
kubectl get events -n bookstore --sort-by='.lastTimestamp'
```

### 3. GitHub Actions Deployment Failing

**Symptoms**: CI/CD pipeline fails during deployment

**Solutions**:
```bash
# Verify AWS credentials
aws sts get-caller-identity

# Check EKS cluster access
aws eks describe-cluster --name bookstore-cluster --region us-east-1

# Test kubectl access
kubectl get nodes
```

### 4. Application Not Accessible

**Symptoms**: ALB DNS returns error or timeout

**Solutions**:
```bash
# Check if pods are running
kubectl get pods -n bookstore

# Verify services
kubectl get svc -n bookstore

# Check ingress
kubectl describe ingress bookstore-ingress -n bookstore

# Test service directly
kubectl port-forward service/bookapp-ui-service 8080:80 -n bookstore
# Then access http://localhost:8080
```

## Debug Commands

### Get All Resources
```bash
kubectl get all -n bookstore
kubectl get ingress -n bookstore
kubectl get events -n bookstore --sort-by='.lastTimestamp'
```

### View Logs
```bash
# Application logs
kubectl logs -f deployment/bookapp-ui -n bookstore
kubectl logs -f deployment/bookapp-api -n bookstore

# AWS Load Balancer Controller logs
kubectl logs -f deployment/aws-load-balancer-controller -n kube-system
```

## Emergency Rollback

```bash
# Rollback to previous deployment
kubectl rollout undo deployment/bookapp-ui -n bookstore
kubectl rollout undo deployment/bookapp-api -n bookstore

# Check rollout history
kubectl rollout history deployment/bookapp-ui -n bookstore
```

## Complete Reset

```bash
# Delete namespace (removes all resources)
kubectl delete namespace bookstore

# Reapply deployment
kubectl apply -f kubernetes/bookstore-deployment.yml

# Wait for ALB to be ready (3-5 minutes)
```
