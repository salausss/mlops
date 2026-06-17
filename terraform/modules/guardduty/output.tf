output "detector_id" {
  value = aws_guardduty_detector.this.id
}

output "findings_bucket" {
  value = aws_s3_bucket.guardduty_findings.bucket
}

output "sns_topic_arn" {
  value = aws_sns_topic.guardduty_findings.arn
}