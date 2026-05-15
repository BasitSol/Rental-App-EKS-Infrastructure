variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "api_container_port" {
  type    = number
  default = 4000
}

variable "restrict_alb_to_cloudfront" {
  type    = bool
  default = true
}

variable "allow_api_public_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_internal_mongo" {
  type    = bool
  default = false
}

variable "service_security_group_id_for_mongo" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "elk_enabled" {
  description = "Enable ELK stack security groups"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "VPC CIDR block for internal ELK traffic rules"
  type        = string
}