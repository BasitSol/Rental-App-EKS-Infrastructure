# Kubernetes Layout

## Production source of truth

In EKS production, Kubernetes resources are managed by Terraform's Kubernetes and Helm providers in [terraform/environments/eks-production/kubernetes.tf](../terraform/environments/eks-production/kubernetes.tf). The CI/CD pipeline at [.github/workflows/deploy.yml](../.github/workflows/deploy.yml) runs `terraform apply` on every push to `main`, so the namespace, RBAC, deployments, services, HPA, PDBs, ingress, network policies, External Secrets, and the platform Helm releases (`ingress-nginx`, `cert-manager`, `metrics-server`, `external-secrets`) all come from Terraform.

The Kustomize layout in this folder is retained for two reasons:

1. **Local Minikube development** uses [overlays/minikube](overlays/minikube) with an in-cluster MongoDB.
2. **Manual fallback for break-glass** uses [overlays/eks-production](overlays/eks-production) and [run-eks.sh](run-eks.sh) when CI is unavailable. This path may drift from Terraform-managed state and should not be used routinely.

## Structure

- `base/`: Common, environment-agnostic resources.
- `overlays/minikube/`: Local Minikube deployment (includes MongoDB in-cluster).
- `overlays/eks-production/`: Manual-fallback overlay for the EKS environment. Image digests, ingress hostname, and IRSA role ARN are placeholders because Terraform owns those values in production. Replace them with real values only if you are using this path as a one-off break-glass deploy.

## Why this layout

- Separation of concerns: common resources stay in one place.
- Environment safety: local and production settings are explicitly isolated.
- Easier reviews: smaller files by concern (ingress, deployment, scaling, etc.).

## Minikube deploy

Fast path (single command after reopening VS Code):

```bash
chmod +x k8s/run-minikube.sh
./k8s/run-minikube.sh
```

Optional flags:

```bash
./k8s/run-minikube.sh --skip-build
./k8s/run-minikube.sh --skip-hosts
./k8s/run-minikube.sh --profile minikube
```

1. Build images inside Minikube Docker daemon:

```bash
minikube -p minikube docker-env | source /dev/stdin
cd api-staging && docker build -t rental-backend:v1 .
cd ../client-staging && docker build -t rental-frontend:v1 .
```

2. Use a CNI that enforces NetworkPolicy:

```bash
minikube start --cni=calico
```

3. Enable ingress:

```bash
minikube addons enable ingress
```

4. Prepare local secrets:

```bash
cp k8s/overlays/minikube/secrets.env.example k8s/overlays/minikube/secrets.env
cp k8s/overlays/minikube/mongo-credentials.env.example k8s/overlays/minikube/mongo-credentials.env
```

5. Add host entry:

```bash
echo "$(minikube ip) rental.local" | sudo tee -a /etc/hosts
```

6. Deploy:

```bash
kubectl apply -k k8s/overlays/minikube
```

## EKS production deploy

Do this through CI. Push to `main` (or run the workflow manually) and the GitHub Actions pipeline will run `terraform apply` and verify the rollout. See the root [README](../README.md) for the full pipeline description.

If you must apply locally as break-glass, run from a workstation that already has cluster-admin access via Access Entries:

```bash
cd terraform/environments/eks-production
terraform init
terraform apply
```

The Kustomize fallback in [run-eks.sh](run-eks.sh) is for local debugging only. Before using it, replace the placeholder image digests, ingress hostname, and IRSA role ARN in [overlays/eks-production](overlays/eks-production) with real values, otherwise the apply will fail or drift from Terraform-managed state.

## Notes

- For real production, move secrets to External Secrets (Vault/AWS Secrets Manager/GCP Secret Manager).
- For production data, use managed MongoDB (Atlas/Azure Cosmos Mongo API/AWS DocumentDB) instead of in-cluster single-node Mongo.
- Add observability stack (Prometheus + Grafana + logs) and backup/restore workflows.

## Verification

- Use `k8s/verification-runbook.md` for post-deploy smoke tests (network policies, ingress controls, PDB behavior, and secret rotation).
