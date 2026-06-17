variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST or PROVISIONED"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "read_capacity" {
  type    = number
  default = null
}

variable "write_capacity" {
  type    = number
  default = null
}

variable "hash_key" {
  type = string
}

variable "hash_key_type" {
  type    = string
  default = "S"
}

variable "range_key" {
  type    = string
  default = null
}

variable "range_key_type" {
  type    = string
  default = "S"
}

variable "extra_attributes" {
  description = "Additional attributes used only by GSIs (name + type)"
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "ttl_attribute_name" {
  description = "Attribute name for TTL (epoch seconds). Leave null to disable."
  type        = string
  default     = null
}

variable "global_secondary_indexes" {
  type = list(object({
    name             = string
    hash_key         = string
    range_key        = optional(string)
    projection_type  = optional(string, "ALL")
    read_capacity    = optional(number)
    write_capacity   = optional(number)
  }))
  default = []
}

variable "point_in_time_recovery" {
  type    = bool
  default = true
}

variable "deletion_protection_enabled" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}