variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "env" {
  type  = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (NAT lives here)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway for private subnets"
  type        = bool
  default     = true
}

variable "cluster_name" {
  type = string
}