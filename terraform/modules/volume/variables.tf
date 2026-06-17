variable "cluster_name"          { type = string }
variable "environment"           { type = string }
variable "vpc_id"                { type = string }
variable "private_subnet_ids"    { type = list(string) }
variable "node_security_group_id" { type = string }
variable "kms_key_arn"             { type = string }
