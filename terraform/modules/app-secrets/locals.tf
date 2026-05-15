locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  secret_names = {
    mongodb_uri    = "${var.secret_prefix}/mongodb_uri"
    session_secret = "${var.secret_prefix}/session_secret"
    jwt_secret     = "${var.secret_prefix}/jwt_secret"
  }
}