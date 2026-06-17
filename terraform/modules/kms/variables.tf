variable "name" {
  description = "Name tag for the KMS key"
  type        = string
}

variable "alias" {
  description = "Alias for the KMS key (without 'alias/' prefix)"
  type        = string
}

variable "description" {
  description = "Description for the KMS key"
  type        = string
}

variable "environment" {
  description = "Environment (e.g., dev, prod)"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Number of days before KMS key is deleted after destruction"
  type        = number
  default     = 10
}

variable "enable_key_rotation" {
  description = "Whether to enable automatic yearly rotation of the key"
  type        = bool
  default     = true
}
