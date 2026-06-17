output "alb_arn" {
  value       = data.aws_lb.taskflow.arn
  description = "ARN of the ALB provisioned by LBC for the taskflow ingress"
}