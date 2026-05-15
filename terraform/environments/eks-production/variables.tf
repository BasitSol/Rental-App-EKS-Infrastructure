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
  description = "CIDRs allowed to reach the EKS public API endpoint. Narrow this before production cutover."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum node count for the managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count for the managed node group."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired node count for the managed node group."
  type        = number
  default     = 2
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