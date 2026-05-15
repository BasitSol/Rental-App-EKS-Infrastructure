output "mongodb_uri_name" {
  value       = aws_secretsmanager_secret.mongodb_uri.name
  description = "Secrets Manager name for the MongoDB URI."
}

output "session_secret_name" {
  value       = aws_secretsmanager_secret.session_secret.name
  description = "Secrets Manager name for the session secret."
}

output "jwt_secret_name" {
  value       = aws_secretsmanager_secret.jwt_secret.name
  description = "Secrets Manager name for the JWT secret."
}

output "secret_prefix" {
  value       = var.secret_prefix
  description = "Secrets Manager prefix used for the app secrets."
}