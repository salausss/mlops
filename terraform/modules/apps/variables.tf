variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "rag-api"
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for your existing EKS cluster, e.g. arn:aws:iam::<account_id>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<cluster_oidc_id>"
  type        = string
}

variable "oidc_provider_url" {
  description = "Same OIDC provider, without the https:// prefix, e.g. oidc.eks.ap-south-1.amazonaws.com/id/<cluster_oidc_id>"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the service will run in"
  type        = string
  default     = "app"
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name that will assume the IRSA role"
  type        = string
  default     = "rag-api-sa"
}

variable "knowledge_base_id" {
  description = "Bedrock Knowledge Base ID from Phase 1/2 (used as a Deployment env var, not by Terraform itself)"
  type        = string
}

variable "model_id" {
  description = "Bedrock model ID / inference profile ID (used as a Deployment env var, not by Terraform itself)"
  type        = string
}
