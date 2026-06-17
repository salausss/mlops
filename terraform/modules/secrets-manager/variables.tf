variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS CMK ARN for encrypting secrets"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace for app workloads"
  type        = string
  default     = "app"
}

variable "db_namespace" {
  description = "Kubernetes namespace for db workloads"
  type        = string
  default     = "db"
}

variable "app_service_account" {
  description = "Kubernetes service account name for TaskFlow app"
  type        = string
  default     = "taskflow-sa"
}

variable "db_service_account" {
  description = "Kubernetes service account name for DB workloads"
  type        = string
  default     = "taskflow-db-sa"
}

variable "rotation_days" {
  description = "Number of days between automatic secret rotations"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}