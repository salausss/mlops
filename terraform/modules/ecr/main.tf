resource "aws_ecr_repository" "repositories" {
  for_each = toset(var.repository_names)

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
    Environment = var.environment
  }
}
