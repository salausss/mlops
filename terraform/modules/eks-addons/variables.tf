variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "enable_efs" {
  description = "Whether to deploy the EFS CSI driver (only needed for shared/RWX volumes)"
  type        = bool
  default     = true
}

variable "enable_cluster_autoscaler" {
  description = "Whether to deploy Cluster Autoscaler"
  type        = bool
  default     = false
}