# Tear Down

Instructions for cleanly removing all resources — local or AWS.

---

## Local (k3d)

```bash
k3d cluster delete bookstore
```

This removes the cluster, all pods, services, and ingress resources. Your local Docker images are unaffected.

---

## AWS (EKS)

Resources must be deleted in order. Terraform cannot destroy the VPC if the ALB or EKS still have resources attached.

### 1. Remove Helm releases

```bash
# Remove monitoring stack
helm uninstall prometheus -n monitoring

# Remove AWS Load Balancer Controller
helm uninstall aws-load-balancer-controller -n kube-system
```

> **Why first?** The LB controller creates AWS ALB resources outside of Terraform's state. If you run `terraform destroy` while the controller is still running, the ALB may remain and block VPC deletion.

### 2. Delete Kubernetes resources

```bash
kubectl delete -f k8s/
```

### 3. Destroy Terraform infrastructure

```bash
cd terraform
terraform destroy
```

This removes: EKS cluster, node group, VPC, subnets, ECR repos, IAM roles, and OIDC provider.

> Terraform destroy can take 10–15 minutes. The EKS cluster deletion is the slowest step.

---

## After Recreating (post-destroy + apply)

When you run `terraform apply` again:
- The cluster name changes (random suffix in `main.tf`)
- The GitHub Actions IAM role ARN changes

You must:
1. Run the two-step Terraform apply again (see [02-aws-setup.md](02-aws-setup.md))
2. Update the `AWS_ROLE_ARN` secret in GitHub repository settings
3. Run `./bootstrap.sh` again

---

## Verify Everything Is Removed

```bash
# No EKS clusters
aws eks list-clusters --region us-east-1

# No ECR repos
aws ecr describe-repositories --region us-east-1

# No ALBs
aws elbv2 describe-load-balancers --region us-east-1 | grep bookstore
```
