variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID where ELK services will run"
  type        = string
}

variable "elasticsearch_sg_id" {
  type = string
}

variable "logstash_sg_id" {
  type = string
}

variable "kibana_sg_id" {
  type = string
}

variable "kibana_target_group_arn" {
  description = "ALB target group ARN for Kibana service"
  type        = string
}

variable "efs_sg_id" {
  type = string
}

variable "elasticsearch_password" {
  type      = string
  sensitive = true
}

variable "aws_region" {
  type = string
}

variable "elk_version" {
  type = string
  #default = "8.11.0"
  default = "7.17.18"
}

variable "elasticsearch_cpu" {
  type    = number
  default = 2048
}

variable "elasticsearch_memory" {
  type    = number
  default = 4096
}

variable "logstash_cpu" {
  type    = number
  default = 1024
}

variable "logstash_memory" {
  type    = number
  default = 2048
}

variable "kibana_cpu" {
  type    = number
  default = 512
}

variable "kibana_memory" {
  type    = number
  default = 1024
}

variable "tags" {
  type    = map(string)
  default = {}
}