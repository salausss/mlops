output "amp_workspace_id" {
  value = aws_prometheus_workspace.this.id
}

output "amp_remote_write_url" {
  value = aws_prometheus_workspace.this.prometheus_endpoint
}

output "grafana_workspace_url" {
  value = aws_grafana_workspace.this.endpoint
}

output "adot_role_arn" {
  value = aws_iam_role.adot_role.arn
}