output "vpc_id" {
  description = "VPC ID for the EKS environment."
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for the EKS environment."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs for the EKS environment."
  value       = module.networking.private_subnet_ids
}

output "nat_eip" {
  description = "Elastic IPs for the NAT gateways."
  value       = module.networking.nat_eip
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded EKS cluster CA certificate."
  value       = module.eks_cluster.cluster_ca_certificate
  sensitive   = true
}

output "node_group_name" {
  description = "Managed node group name."
  value       = module.eks_cluster.node_group_name
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA use later."
  value       = module.eks_cluster.oidc_provider_arn
}

output "kubectl_config_command" {
  description = "Command to configure kubectl for the cluster."
  value       = module.eks_cluster.kubectl_config_command
}

output "app_secret_prefix" {
  description = "Secrets Manager prefix used by the app secrets."
  value       = module.app_secrets.secret_prefix
}

output "mongodb_uri_secret_name" {
  description = "Secrets Manager name for the MongoDB URI."
  value       = module.app_secrets.mongodb_uri_name
}

output "session_secret_name" {
  description = "Secrets Manager name for the session secret."
  value       = module.app_secrets.session_secret_name
}

output "jwt_secret_name" {
  description = "Secrets Manager name for the JWT secret."
  value       = module.app_secrets.jwt_secret_name
}