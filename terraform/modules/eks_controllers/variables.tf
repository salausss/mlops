variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "lbc_helm_version" {
  description = "Helm chart version for AWS Load Balancer Controller"
  type        = string
  default     = "1.8.1"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EKS cluster runs"
  type        = string
}
