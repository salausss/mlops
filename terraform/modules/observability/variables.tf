variable "cluster_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "grafana_admin_password" {
  type = string
  default = "Agent12"
}