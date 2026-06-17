variable "project" {
  type = string
}

variable "environment" {
  type = string
}
variable "alert_email" {
  type    = string
  default = ""
  description = "Email address to receive HIGH/MEDIUM finding alerts. Leave empty to skip."
}
