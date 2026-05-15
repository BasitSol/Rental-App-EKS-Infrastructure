variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "api_container_port" {
  type    = number
  default = 4000
}

variable "api_health_check_path" {
  type    = string
  default = "/readyz"
}

variable "frontend_bucket_name" {
  type = string
}

variable "cloudfront_price_class" {
  type    = string
  default = "PriceClass_100"
}

variable "enable_custom_domain" {
  type    = bool
  default = false
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "elk_enabled" {
  description = "Enable Kibana target group and listener rule"
  type        = bool
  default     = false
}

variable "kibana_sg_id" {
  description = "Kibana security group ID for target group"
  type        = string
  default     = null
}