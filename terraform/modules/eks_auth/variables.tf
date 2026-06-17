variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "env" {
  type = string
}

variable "admin_group_name" {
  description = "K8s group name for admins"
  type        = string
  default     = "eks:admin-group"
}

variable "developer_group_name" {
  description = "K8s group name for developers"
  type        = string
  default     = "eks:developer-group"
}

variable "developer_namespaces" {
  description = "List of namespaces developers are allowed to access"
  type        = list(string)
  default     = ["app", "db"]
}

variable "node_group_role" {
  type = string
}

variable "admin_user_arns" {
  description = "List of IAM user ARNs to be added to the admin group"
  type        = list(string)
  default     = []
}

variable "developer_user_arns" {
  description = "List of IAM user ARNs to be added to the developer group"
  type        = list(string)
  default     = []
}