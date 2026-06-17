# outputs.tf

# This file defines the outputs of our Terraform module.

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.primary.name
}

output "cluster_endpoint" {
  description = "The endpoint for your EKS Kubernetes API server."
  value       = aws_eks_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  description = "The certificate authority data for the EKS cluster."
  value       = base64decode(aws_eks_cluster.primary.certificate_authority[0].data)
}

output "oidc_provider_url" {
  description = "The OIDC provider URL for the cluster, used for IAM Roles for Service Accounts (IRSA)."
  #value       = aws_eks_cluster.primary.identity[0].oidc[0].issuer
  value = replace(aws_eks_cluster.primary.identity[0].oidc[0].issuer, "https://", "")   
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "configure_kubectl" {
  description = "A command to configure kubectl to connect to the new EKS cluster."
  value = "aws eks update-kubeconfig --region ${split(":", aws_eks_cluster.primary.arn)[3]} --name ${aws_eks_cluster.primary.name}"
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.primary.vpc_config[0].cluster_security_group_id
}

output "node_group_role" {
  value       = aws_iam_role.node_group_role.arn
}