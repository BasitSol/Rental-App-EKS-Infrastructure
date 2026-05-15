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

After the cluster exists, configure kubectl:

```bash
aws eks update-kubeconfig --region us-east-1 --name rentalapp-eks-prod-eks
```

Then install the Kubernetes add-ons and apply the app manifests with the helper script:

```bash
../../../k8s/run-eks.sh
```

The helper script pulls `MONGODB_URI`, `SESSION_SECRET`, and `JWT_SECRET` from AWS Secrets Manager using the `/rentalapp/eks-prod` prefix by default.

## Notes

- Keep ECS production running until the EKS deployment is validated.
- Narrow `cluster_endpoint_public_access_cidrs` before moving the cluster into real production traffic.
- This environment uses a separate VPC CIDR from the current ECS production stack to avoid overlap during migration.