output "irsa_role_arn" {
  description = "Paste this into k8s/serviceaccount.yaml as the eks.amazonaws.com/role-arn annotation"
  value       = aws_iam_role.irsa.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.conversations.name
}
