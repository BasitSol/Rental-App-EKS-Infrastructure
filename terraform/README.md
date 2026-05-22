# Terraform Infrastructure

This directory uses an environment-wrapper and reusable-modules layout. Terraform is the source of truth for both the AWS foundation and the in-cluster Kubernetes runtime.

## Layout

- `modules/networking`: VPC, subnets, IGW, NAT gateways, and routing.
- `modules/eks-cluster`: EKS control plane, managed node group, core add-ons, OIDC provider, and the External Secrets IAM role.
- `modules/app-secrets`: AWS Secrets Manager entries under `/rentalapp/eks-prod/*`.
- `modules/github-runner`: legacy self-hosted GitHub Actions runner. **No longer used** by the production pipeline; kept for now to avoid disturbing state. Safe to remove in a follow-up cleanup.
- `environments/eks-production`: production environment wrapper. Composes the modules, configures the GitHub Actions OIDC trust + scoped IAM policy, creates the EKS Access Entry that lets CI manage the cluster, and provisions Kubernetes resources via the Kubernetes/Helm providers.

## Backend

State is stored in S3 with DynamoDB locking:

- Bucket: `rentalapp-terraform-state-eks-prod`
- Lock table: `rentalapp-terraform-locks`
- Region: `us-east-1`

## Day-to-day usage

The production deployment path is the GitHub Actions workflow at [.github/workflows/deploy.yml](../.github/workflows/deploy.yml). It runs `terraform plan` on every push to `main` and applies the saved plan in the same job, so engineers should not normally run `terraform apply` from a workstation.

## One-time bootstrap (workstation)

The first apply must come from a workstation because:

1. The GitHub Actions IAM role and OIDC trust do not exist yet, so CI cannot authenticate.
2. The EKS Access Entry that grants the CI role cluster-admin must be created with credentials that already have cluster access.

```bash
cd environments/eks-production
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Provide the application secrets when prompted (or via `-var` flags / `TF_VAR_*` env vars):

- `mongodb_uri`
- `session_secret`
- `jwt_secret`

After this apply, future changes go through CI.

## Break-glass usage

If CI is unavailable and you must apply locally, ensure your IAM principal has cluster-admin via Access Entries (the cluster bootstrap creator already does), then run the same `init`/`plan`/`apply` sequence above.
