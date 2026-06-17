output "key_id" {
  description = "The KMS key ID"
  value       = aws_kms_key.this.key_id
}

output "arn" {
  description = "The ARN of the KMS key"
  value       = aws_kms_key.this.arn
}

output "alias" {
  description = "The KMS key alias"
  value       = aws_kms_alias.this.name
}

output "key_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key."
  value       = aws_kms_key.this.arn # Make sure 'aws_kms_key.kms_key' matches your resource name
}
