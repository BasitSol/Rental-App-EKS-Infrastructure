variable "aws_region" {
  description = "AWS region for the EKS stack."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used in naming and tagging."
  type        = string
  default     = "rentalapp"
}

variable "environment" {
  description = "Environment name used in naming and tagging."
  type        = string
  default     = "eks-prod"
}

variable "secret_prefix" {
  description = "AWS Secrets Manager prefix for app secrets."
  type        = string
  default     = "/rentalapp/eks-prod"
}

variable "tags" {
  description = "Additional tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC. Use a non-overlapping CIDR from ECS production."
  type        = string
  default     = "10.50.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs for the EKS VPC."
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24", "10.50.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs for the EKS worker nodes."
  type        = list(string)
  default     = ["10.50.101.0/24", "10.50.102.0/24", "10.50.103.0/24"]
}

variable "availability_zones" {
  description = "Optional AZ override list. Leave empty to auto-select."
  type        = list(string)
  default     = []
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint. Defaults to 0.0.0.0/0 because GitHub-hosted runners use AWS-wide egress IPs; authorization is enforced by IAM Access Entries, not by network ACLs. Narrow this only if you switch to self-hosted runners with known egress."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group. t3.micro is used because the AWS account is restricted to Free Tier instances. Switch to t3.medium or larger when the restriction is lifted."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_min_size" {
  description = "Minimum node count. t3.micro holds 4 pods each; daemonsets (aws-node + kube-proxy) eat 2 per node, so net 2 usable slots per node. 8 nodes = 16 usable slots, fits the full stack."
  type        = number
  default     = 8
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group."
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 8
}

variable "node_disk_size" {
  description = "EBS disk size in GiB for worker nodes."
  type        = number
  default     = 50
}

variable "mongodb_uri" {
  description = "MongoDB URI stored in AWS Secrets Manager for EKS production."
  type        = string
  sensitive   = true
}

variable "session_secret" {
  description = "Session secret stored in AWS Secrets Manager for EKS production."
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret stored in AWS Secrets Manager for EKS production."
  type        = string
  sensitive   = true
}

variable "external_secrets_enabled" {
  description = "Whether to create the External Secrets IRSA role."
  type        = bool
  default     = true
}

variable "external_secrets_namespace" {
  description = "Namespace for the External Secrets service account."
  type        = string
  default     = "rental"
}

variable "external_secrets_service_account" {
  description = "Service account name used by External Secrets for IRSA."
  type        = string
  default     = "rental-external-secrets"
}

variable "ingress_host" {
  description = "Optional custom hostname for the ingress (e.g. app.yourdomain.com). Leave empty to auto-discover the NLB hostname assigned by AWS - the ingress will then act as catch-all for the NLB. Set this when you have a real domain CNAME'd to the NLB."
  type        = string
  default     = ""
}

variable "api_image" {
  description = "API image reference (tag or digest)."
  type        = string
  default     = "664418980347.dkr.ecr.us-east-1.amazonaws.com/rental/api@sha256:69d65560ead3b308bbb1f22437c394b7f67f912346b8fd3f9fa2dcccef23dc3f"
}

variable "client_image" {
  description = "Client image reference (tag or digest)."
  type        = string
  default     = "664418980347.dkr.ecr.us-east-1.amazonaws.com/rental/client@sha256:4dd68e32bf69eda950197fae577b5c9154f46eb4fea8a74f99c1bfcfd2fd8f09"
}

variable "enable_k8s_resources" {
  description = "Whether to manage Kubernetes and Helm resources via Terraform."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role (owner/repo)."
  type        = string
  default     = "BasitSol/Rental-App-EKS-Infrastructure"
}

variable "github_branch" {
  description = "GitHub branch allowed to assume the CI role."
  type        = string
  default     = "main"
}

variable "github_actions_role_name" {
  description = "IAM role name for GitHub Actions OIDC."
  type        = string
  default     = "rentalapp-gha-deploy"
}

variable "enable_github_runner" {
  description = "Enable EC2 self-hosted GitHub Actions runners in the VPC."
  type        = bool
  default     = false
}

variable "github_runner_app_secret_arn" {
  description = "Secrets Manager ARN containing GitHub App credentials for runner registration."
  type        = string
  default     = ""
}

variable "github_runner_app_kms_key_arn" {
  description = "Optional KMS key ARN for decrypting the GitHub App secret."
  type        = string
  default     = ""
}

variable "github_runner_labels" {
  description = "Labels for self-hosted runners."
  type        = list(string)
  default     = ["eks-runner"]
}

variable "github_runner_group" {
  description = "GitHub runner group name."
  type        = string
  default     = "Default"
}

variable "github_runner_version" {
  description = "GitHub Actions runner version."
  type        = string
  default     = "2.334.0"
}

variable "github_runner_instance_type" {
  description = "Instance type for runner hosts."
  type        = string
  default     = "t3.large"
}

variable "github_runner_min_size" {
  description = "Minimum number of runners in the ASG."
  type        = number
  default     = 1
}

variable "github_runner_max_size" {
  description = "Maximum number of runners in the ASG."
  type        = number
  default     = 3
}

variable "github_runner_desired_capacity" {
  description = "Desired number of runners in the ASG."
  type        = number
  default     = 1
}

variable "github_runner_log_retention_days" {
  description = "CloudWatch log retention for runner logs."
  type        = number
  default     = 14
}

variable "github_runner_ephemeral" {
  description = "Whether runners should be ephemeral per job."
  type        = bool
  default     = true
}