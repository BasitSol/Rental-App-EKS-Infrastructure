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

module "security_groups" {
  source = "../../modules/security-groups"

  project_name                   = var.project_name
  environment                    = var.environment
  vpc_id                         = module.networking.vpc_id
  api_container_port             = var.api_container_port
  restrict_alb_to_cloudfront     = var.restrict_alb_to_cloudfront
  allow_api_public_ingress_cidrs = var.allow_api_public_ingress_cidrs
  enable_internal_mongo          = var.enable_internal_mongo
  tags                           = var.tags
  vpc_cidr                       = module.networking.vpc_cidr_block # ADD THIS
  elk_enabled                    = var.elk_enabled                  # ADD THIS
}

module "load_balancing" {
  source = "../../modules/load-balancing"

  project_name           = var.project_name
  environment            = var.environment
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  alb_security_group_id  = module.security_groups.alb_security_group_id
  api_container_port     = var.api_container_port
  api_health_check_path  = var.api_health_check_path
  frontend_bucket_name   = var.frontend_bucket_name
  cloudfront_price_class = var.cloudfront_price_class
  enable_custom_domain   = var.enable_custom_domain
  domain_name            = var.domain_name
  route53_zone_id        = var.route53_zone_id
  tags                   = var.tags
  elk_enabled            = var.elk_enabled                                 # ADD THIS
  kibana_sg_id           = module.security_groups.kibana_security_group_id # ADD THIS

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

}

module "compute" {
  source = "../../modules/compute"

  project_name                     = var.project_name
  environment                      = var.environment
  aws_region                       = var.aws_region
  vpc_id                           = module.networking.vpc_id
  subnet_ids                       = module.networking.private_subnet_ids
  assign_public_ip                 = false
  service_security_group_id        = module.security_groups.ecs_service_security_group_id
  target_group_arn                 = module.load_balancing.api_target_group_arn
  api_container_port               = var.api_container_port
  api_cpu                          = var.api_cpu
  api_memory                       = var.api_memory
  api_desired_count                = var.api_desired_count
  api_min_capacity                 = var.api_min_capacity
  api_max_capacity                 = var.api_max_capacity
  api_image_tag                    = var.api_image_tag
  api_image_override               = var.api_image_override
  api_log_retention_days           = var.api_log_retention_days
  frontend_public_url              = module.load_balancing.frontend_url
  create_ssm_parameters            = var.create_ssm_parameters
  ssm_parameter_prefix             = var.ssm_parameter_prefix
  mongodb_uri                      = var.mongodb_uri
  session_secret                   = var.session_secret
  jwt_secret                       = var.jwt_secret
  existing_ssm_mongodb_uri_name    = var.existing_ssm_mongodb_uri_name
  existing_ssm_session_secret_name = var.existing_ssm_session_secret_name
  existing_ssm_jwt_secret_name     = var.existing_ssm_jwt_secret_name
  enable_internal_mongo            = var.enable_internal_mongo
  mongo_instance_type              = var.mongo_instance_type
  mongo_security_group_id          = module.security_groups.mongo_security_group_id
  tags                             = var.tags
  elk_enabled                      = var.elk_enabled                                                                    # ADD THIS
  logstash_endpoint                = var.elk_enabled ? "logstash.${var.project_name}-${var.environment}-elk.local" : "" # ADD THIS

  depends_on = [module.load_balancing]
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name                = var.project_name
  environment                 = var.environment
  enable_alerts               = var.enable_alerts
  alert_email                 = var.alert_email
  alb_arn_suffix              = module.load_balancing.alb_arn_suffix
  api_target_group_arn_suffix = module.load_balancing.api_target_group_arn_suffix
  ecs_cluster_name            = module.compute.ecs_cluster_name
  ecs_service_name            = module.compute.ecs_service_name
  monthly_budget_limit_usd    = var.monthly_budget_limit_usd
  budget_alert_email          = var.budget_alert_email
  tags                        = var.tags
}

module "dns" {
  source = "../../modules/dns"
  count  = var.enable_custom_domain ? 1 : 0

  project_name              = var.project_name
  environment               = var.environment
  enable_custom_domain      = var.enable_custom_domain
  domain_name               = var.domain_name
  route53_zone_id           = var.route53_zone_id
  cloudfront_domain_name    = module.load_balancing.cloudfront_domain_name
  cloudfront_hosted_zone_id = module.load_balancing.cloudfront_hosted_zone_id
  tags                      = var.tags

  providers = {
    aws = aws
  }
}

# -------------------------------------------------------------------------
# ELK Stack Module
# -------------------------------------------------------------------------
module "elk" {
  count  = var.elk_enabled ? 1 : 0
  source = "../../modules/elk"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  ecs_cluster_id     = module.compute.ecs_cluster_id
  aws_region         = var.aws_region

  elasticsearch_sg_id     = module.security_groups.elasticsearch_security_group_id
  logstash_sg_id          = module.security_groups.logstash_security_group_id
  kibana_sg_id            = module.security_groups.kibana_security_group_id
  kibana_target_group_arn = module.load_balancing.kibana_target_group_arn
  efs_sg_id               = module.security_groups.elk_efs_security_group_id

  elasticsearch_password = var.elasticsearch_password
  elk_version            = var.elk_version
  elasticsearch_cpu      = var.elasticsearch_cpu
  elasticsearch_memory   = var.elasticsearch_memory
  logstash_cpu           = var.logstash_cpu
  logstash_memory        = var.logstash_memory
  kibana_cpu             = var.kibana_cpu
  kibana_memory          = var.kibana_memory
  tags                   = var.tags
}