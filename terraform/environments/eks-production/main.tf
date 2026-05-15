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