variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "enable_alerts" {
  type    = bool
  default = true
}

variable "alert_email" {
  type    = string
  default = ""
}

variable "alb_arn_suffix" {
  type = string
}

variable "api_target_group_arn_suffix" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "monthly_budget_limit_usd" {
  type    = number
  default = 150
}

variable "budget_alert_email" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
