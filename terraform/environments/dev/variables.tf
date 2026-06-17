# General variables
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
    type      = string
}

variable "project_name" {
    type = string
}

## Networking variables
variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

# AWS user Authentication 
variable "admin_user_arns" {
  description = "List of IAM user ARNs to be added to the admin group"
  type        = list(string)
  default     = []
}

variable "developer_user_arns" {
  description = "List of IAM user ARNs to be added to the developer group"
  type        = list(string)
  default     = []
}