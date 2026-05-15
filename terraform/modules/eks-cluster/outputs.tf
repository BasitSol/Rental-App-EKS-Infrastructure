output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name."
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS API server endpoint."
}

output "cluster_ca_certificate" {
  value       = aws_eks_cluster.main.certificate_authority[0].data
  description = "Base64-encoded cluster CA certificate."
}

output "node_group_name" {
  value       = aws_eks_node_group.main.node_group_name
  description = "Managed node group name."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.main.arn
  description = "OIDC provider ARN for IRSA."
}

output "oidc_issuer_url" {
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
  description = "OIDC issuer URL for the cluster."
}

output "kubectl_config_command" {
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
  description = "Command to configure kubectl for the cluster."
}