output "repository_urls" {
  description = "URLs of the created ECR repositories"
  value       = { for k, repo in aws_ecr_repository.repositories : k => repo.repository_url }
}
