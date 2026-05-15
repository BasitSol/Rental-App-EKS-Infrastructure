variable "project_name" {
  type = string
}

variable "environment" {
  type = string
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

variable "cloudfront_domain_name" {
  type = string
}

variable "cloudfront_hosted_zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
