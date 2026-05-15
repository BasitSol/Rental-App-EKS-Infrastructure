variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "secret_prefix" {
  description = "AWS Secrets Manager path prefix for application secrets."
  type        = string
}

variable "mongodb_uri" {
  description = "MongoDB URI stored in Secrets Manager."
  type        = string
  sensitive   = true
}

variable "session_secret" {
  description = "Session secret stored in Secrets Manager."
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret stored in Secrets Manager."
  type        = string
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}