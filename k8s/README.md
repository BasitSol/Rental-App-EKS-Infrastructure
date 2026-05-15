# Kubernetes Layout (Production-Oriented)

This folder now uses Kustomize with a base + overlays pattern.

## Structure

- `base/`: Common, environment-agnostic resources.
- `overlays/minikube/`: Local Minikube deployment (includes MongoDB in-cluster).
- `overlays/production/`: Production deployment (expects managed external MongoDB).

## Why this is better than a single giant YAML

- Separation of concerns: common resources stay in one place.
- Environment safety: local and production settings are explicitly isolated.
- Better CI/CD ergonomics: deploy with one command per environment.
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

## Production deploy

1. Copy secret example and fill real values (or inject from CI):

```bash
cp k8s/overlays/production/secrets.env.example k8s/overlays/production/secrets.env
```

2. Create TLS certificate secret:

```bash
kubectl -n rental create secret tls rental-tls \
  --cert=/path/to/fullchain.pem \
  --key=/path/to/privkey.pem
```

3. Deploy:

```bash
kubectl apply -k k8s/overlays/production
```

## EKS migration deploy

Use this path once the EKS Terraform environment exists and the cluster is reachable:

```bash
cd terraform/environments/eks-production
terraform init
terraform apply
```

Then install the cluster add-ons and deploy the application:

```bash
../../../k8s/run-eks.sh
```

The EKS path uses AWS Secrets Manager to hydrate the application secret file at deploy time, then reuses the Kubernetes production overlay with the `letsencrypt-prod` ClusterIssuer and the NGINX ingress class. Keep the existing ECS stack running until the EKS rollout is healthy.

## Notes

- For real production, move secrets to External Secrets (Vault/AWS Secrets Manager/GCP Secret Manager).
- For production data, use managed MongoDB (Atlas/Azure Cosmos Mongo API/AWS DocumentDB) instead of in-cluster single-node Mongo.
- Add observability stack (Prometheus + Grafana + logs) and backup/restore workflows.

## Verification

- Use `k8s/verification-runbook.md` for post-deploy smoke tests (network policies, ingress controls, PDB behavior, and secret rotation).
