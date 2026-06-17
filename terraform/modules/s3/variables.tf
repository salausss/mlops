variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "force_destroy" {
  description = "Allow Terraform to destroy the bucket even if it contains objects"
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Enable versioning on the bucket"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable server-side encryption"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS encryption. Leave null for SSE-S3 (AES256)"
  type        = string
  default     = null
}

variable "block_public_access" {
  description = "Block all public access to the bucket"
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "Enable lifecycle rules"
  type        = bool
  default     = false
}

variable "lifecycle_rules" {
  description = "List of lifecycle rule objects"
  type = list(object({
    id                         = string
    enabled                    = bool
    prefix                     = optional(string)
    expiration_days            = optional(number)
    noncurrent_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = []
}

variable "enable_logging" {
  description = "Enable access logging for the bucket"
  type        = bool
  default     = false
}

variable "logging_target_bucket" {
  description = "Target bucket for access logs (required if enable_logging is true)"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefix for access logs in the target bucket"
  type        = string
  default     = "log/"
}

variable "bucket_policy" {
  description = "Raw JSON bucket policy document. Leave null to skip attaching a policy"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the bucket"
  type        = map(string)
  default     = {}
}
