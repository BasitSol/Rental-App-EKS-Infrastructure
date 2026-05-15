variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  description = "AWS region for the cluster."
  type        = string
}

variable "cluster_subnet_ids" {
  description = "Subnets used by the EKS control plane."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Private subnets used by the managed node group."
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

variable "cluster_endpoint_private_access" {
  type    = bool
  default = true
}

variable "cluster_endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_disk_size" {
  type    = number
  default = 50
}

variable "tags" {
  type    = map(string)
  default = {}
}