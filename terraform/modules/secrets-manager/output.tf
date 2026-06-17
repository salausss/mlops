output "taskflow_app_secret_arn" {
  description = "ARN of the TaskFlow app secret"
  value       = aws_secretsmanager_secret.taskflow_app.arn
}

output "taskflow_app_secret_name" {
  description = "Name of the TaskFlow app secret"
  value       = aws_secretsmanager_secret.taskflow_app.name
}

output "taskflow_db_secret_arn" {
  description = "ARN of the TaskFlow DB secret"
  value       = aws_secretsmanager_secret.taskflow_db.arn
}

output "taskflow_db_secret_name" {
  description = "Name of the TaskFlow DB secret"
  value       = aws_secretsmanager_secret.taskflow_db.name
}

output "app_sa_role_arn" {
  description = "IAM role ARN for app namespace service account"
  value       = aws_iam_role.app_sa.arn
}

output "db_sa_role_arn" {
  description = "IAM role ARN for db namespace service account"
  value       = aws_iam_role.db_sa.arn
}

output "app_service_account_name" {
  description = "Kubernetes service account name for app namespace"
  value       = kubernetes_service_account_v1.taskflow_app.metadata[0].name
}

output "db_service_account_name" {
  description = "Kubernetes service account name for db namespace"
  value       = kubernetes_service_account_v1.taskflow_db.metadata[0].name
}

output "rotation_lambda_arn" {
  description = "ARN of the secret rotation Lambda"
  value       = aws_lambda_function.secret_rotation.arn
}