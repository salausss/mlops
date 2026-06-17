variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (without https://)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "db_secret_name" {
  description = "Kubernetes secret name for DB credentials"
  type        = string
  default     = "taskflow-db-credentials"
}

variable "db_namespace" {
  description = "Namespace where CNPG cluster is deployed"
  type        = string
  default     = "db"
}

variable "storage_size" {
  description = "PVC size for Postgres data"
  type        = string
  default     = "5Gi"
}

variable "postgres_instances" {
  description = "Number of Postgres instances"
  type        = number
  default     = 1
}

variable "wal_retention_days" {
  description = "WAL archive retention in days"
  type        = number
  default     = 7
}

variable "backup_schedule" {
  description = "Cron schedule for full backups"
  type        = string
  default     = "0 2 * * *"
}