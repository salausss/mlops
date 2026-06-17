variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "allowed_ip_cidrs" {
  type        = list(string)
  description = "Optional IP allowlist CIDRs. Empty = no IP restriction."
  default     = []
}

variable "rate_limit" {
  type        = number
  description = "Max requests per 5-minute window per IP"
  default     = 2000
}

variable "enable_logging" {
  type        = bool
  default     = true
}

variable "log_bucket_arn" {
  type        = string
  description = "S3 bucket ARN for WAF logs (must start with aws-waf-logs-)"
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
