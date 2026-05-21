# EKS Production Environment

This environment creates the AWS foundation for running the RentalApp workloads on EKS instead of ECS Fargate.

## What it creates

- A dedicated VPC with public and private subnets.
- An EKS control plane with managed node groups.
- Core EKS add-ons needed for basic cluster operation.
- An OIDC provider so IRSA-ready add-ons can be enabled later.

## How to use it

```bash
cd terraform/environments/eks-production
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform also installs the cluster add-ons (ingress-nginx, cert-manager, metrics-server, external-secrets) and applies the application manifests via the Kubernetes and Helm providers. This removes the need for the helper script.

## Self-hosted GitHub Actions runner

To run CI inside the VPC (required for private EKS access), enable the EC2 runner module.

1) Create a GitHub App with Actions runner permissions for the repo.
2) Store the GitHub App credentials in AWS Secrets Manager as JSON:

```json
{
	"app_id": "123456",
	"installation_id": "12345678",
	"private_key_pem": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
}
```

3) Set Terraform variables:

```hcl
enable_github_runner        = true
github_runner_app_secret_arn = "arn:aws:secretsmanager:...:secret:github-app"
```

4) Ensure the workflow targets the runner label `eks-runner`.

## Notes

- Keep ECS production running until the EKS deployment is validated.
- Narrow `cluster_endpoint_public_access_cidrs` before moving the cluster into real production traffic.
- This environment uses a separate VPC CIDR from the current ECS production stack to avoid overlap during migration.