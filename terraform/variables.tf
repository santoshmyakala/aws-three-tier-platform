variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "three-tier"
}

variable "environment" {
  description = "Environment name, used in tags and names."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region. Must have at least three availability zones."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC; split into /20 subnets per tier and AZ."
  type        = string
  default     = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cheaper) instead of one per AZ (highly available)."
  type        = bool
  default     = true
}

variable "web_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_instance_type" {
  type    = string
  default = "t3.small"
}

variable "db_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "vpn_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "web_capacity" {
  description = "Min, desired and max size of the Nginx tier."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 2 }
}

variable "app_capacity" {
  description = "Min, desired and max size of the Node.js tier."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 3 }
}

variable "vpn_allowed_cidrs" {
  description = "Client CIDRs allowed to reach the WireGuard endpoint (UDP 51820)."
  type        = list(string)

  validation {
    condition     = length(var.vpn_allowed_cidrs) > 0 && alltrue([for c in var.vpn_allowed_cidrs : can(cidrnetmask(c))])
    error_message = "Provide at least one valid IPv4 CIDR, e.g. your office or home IP as x.x.x.x/32."
  }
}

variable "vpn_client_cidr" {
  description = "Tunnel address range handed to WireGuard clients."
  type        = string
  default     = "10.99.0.0/24"
}

variable "certificate_arn" {
  description = "Optional ACM certificate ARN. When set, the public ALB serves HTTPS and redirects HTTP."
  type        = string
  default     = null
}
