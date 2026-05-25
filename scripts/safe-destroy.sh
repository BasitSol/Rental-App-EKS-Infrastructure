#!/usr/bin/env bash
set -euo pipefail

echo "=== Safe EKS Destroy ==="
echo "This script destroys the EKS infrastructure while preserving resources"
echo "required for GitHub Actions workflows to continue functioning."
echo ""

DIR="terraform/environments/eks-production"

# 1. Verify AWS credentials are configured
echo "[1/5] Verifying AWS credentials..."
aws sts get-caller-identity > /dev/null

# 2. Preserve workflow-critical IAM resources by removing them from state
echo "[2/5] Preserving GitHub Actions IAM resources..."
terraform -chdir="$DIR" state rm 'aws_iam_openid_connect_provider.github' 2>/dev/null || true
terraform -chdir="$DIR" state rm 'aws_iam_role.github_actions' 2>/dev/null || true
terraform -chdir="$DIR" state rm 'aws_iam_policy.github_actions_deploy' 2>/dev/null || true
terraform -chdir="$DIR" state rm 'aws_iam_role_policy_attachment.github_actions_deploy' 2>/dev/null || true

# 3. Drop K8s/Helm resources from state to avoid auth errors during destroy
echo "[3/5] Removing K8s/Helm resources from Terraform state..."
targets=$(terraform -chdir="$DIR" state list 2>/dev/null | grep -E '^(helm_release|kubernetes_|kubectl_manifest|data\.kubernetes_|aws_eks_access_entry|aws_eks_access_policy_association)' || true)
for t in $targets; do
  echo "  Removing $t"
  terraform -chdir="$DIR" state rm "$t" 2>/dev/null || true
done

# 4. Clean up cluster-side K8s resources to avoid orphaned resources
echo "[4/5] Cleaning up cluster resources..."
aws eks update-kubeconfig --name rentalapp-eks-prod-eks --region us-east-1 2>/dev/null || true
if kubectl cluster-info >/dev/null 2>&1; then
  for ns in rental ingress-nginx cert-manager external-secrets; do
    kubectl delete namespace "$ns" --ignore-not-found --wait=false 2>/dev/null || true
  done
  for release in external-secrets cert-manager metrics-server ingress-nginx; do
    ns=$(helm list --all-namespaces 2>/dev/null | awk -v r="$release" '$1==r{print $2}')
    if [ -n "$ns" ]; then
      helm uninstall "$release" -n "$ns" 2>/dev/null || true
    fi
  done
fi

# 5. Destroy the infrastructure
echo "[5/5] Running terraform destroy..."
terraform -chdir="$DIR" destroy -auto-approve

echo ""
echo "=== Destroy complete ==="
echo "Preserved for workflow continuity:"
echo "  - OIDC provider (token.actions.githubusercontent.com)"
echo "  - IAM role (rentalapp-gha-deploy)"
echo "  - IAM policy (rentalapp-gha-deploy-deploy)"
echo ""
echo "Remaining infrastructure has been destroyed."
echo "Run the Deploy EKS workflow when you're ready to recreate."
