module "networking" {
  source = "../../modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  tags                 = var.tags
}

module "eks_cluster" {
  source = "../../modules/eks-cluster"

  project_name                         = var.project_name
  environment                          = var.environment
  aws_region                           = var.aws_region
  cluster_subnet_ids                   = concat(module.networking.public_subnet_ids, module.networking.private_subnet_ids)
  node_subnet_ids                      = module.networking.private_subnet_ids
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  node_instance_types                  = var.node_instance_types
  node_min_size                        = var.node_min_size
  node_max_size                        = var.node_max_size
  node_desired_size                    = var.node_desired_size
  node_disk_size                       = var.node_disk_size
  tags                                 = var.tags
  external_secrets_enabled             = var.external_secrets_enabled
  external_secrets_namespace           = var.external_secrets_namespace
  external_secrets_service_account     = var.external_secrets_service_account
  external_secrets_secret_prefix       = var.secret_prefix
}

module "app_secrets" {
  source = "../../modules/app-secrets"

  project_name   = var.project_name
  environment    = var.environment
  secret_prefix  = var.secret_prefix
  mongodb_uri    = var.mongodb_uri
  session_secret = var.session_secret
  jwt_secret     = var.jwt_secret
  tags           = var.tags
}

locals {
  github_owner = split("/", var.github_repo)[0]
  github_repo  = split("/", var.github_repo)[1]
}

module "github_runner" {
  source = "../../modules/github-runner"
  count  = var.enable_github_runner ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  tags         = var.tags

  vpc_id     = module.networking.vpc_id
  vpc_cidr   = module.networking.vpc_cidr_block
  subnet_ids = module.networking.private_subnet_ids

  github_owner                 = local.github_owner
  github_repo                  = local.github_repo
  github_runner_group          = var.github_runner_group
  github_runner_labels         = var.github_runner_labels
  github_app_secret_arn        = var.github_runner_app_secret_arn
  github_app_secret_kms_key_arn = var.github_runner_app_kms_key_arn

  runner_version  = var.github_runner_version
  instance_type   = var.github_runner_instance_type
  min_size        = var.github_runner_min_size
  max_size        = var.github_runner_max_size
  desired_capacity = var.github_runner_desired_capacity
  log_retention_days = var.github_runner_log_retention_days
  enable_ephemeral   = var.github_runner_ephemeral
}

# Grant the GitHub Actions CI/CD role access to the EKS cluster API
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks_cluster.cluster_name
  principal_arn = aws_iam_role.github_actions.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks_cluster.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_iam_role.github_actions.arn
  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}