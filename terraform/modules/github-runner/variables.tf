variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_runner_group" {
  type    = string
  default = "Default"
}

variable "github_runner_labels" {
  type    = list(string)
  default = ["eks-runner"]
}

variable "github_app_secret_arn" {
  type = string
}

variable "github_app_secret_kms_key_arn" {
  type    = string
  default = ""
}

variable "runner_version" {
  type    = string
  default = "2.316.0"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "enable_ephemeral" {
  type    = bool
  default = true
}
