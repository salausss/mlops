# ─────────────────────────────────────────────────────────────
# OIDC PROVIDER OUTPUT
# ─────────────────────────────────────────────────────────────

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider created for this cluster"
  value       = data.aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer" {
  description = "OIDC issuer URL (without https://)"
  value       = local.oidc_issuer
}

# ─────────────────────────────────────────────────────────────
# EKS MANAGED ADDON OUTPUTS
# ─────────────────────────────────────────────────────────────

output "vpc_cni_addon_id" {
  value = aws_eks_addon.vpc_cni.id
}

output "coredns_addon_id" {
  value = aws_eks_addon.coredns.id
}

output "kube_proxy_addon_id" {
  value = aws_eks_addon.kube_proxy.id
}

output "ebs_csi_addon_id" {
  value = aws_eks_addon.ebs_csi_driver.id
}

output "efs_csi_addon_id" {
  value = var.enable_efs ? aws_eks_addon.efs_csi_driver[0].id : null
}

# ─────────────────────────────────────────────────────────────
# IRSA ROLE ARN OUTPUTS
# ─────────────────────────────────────────────────────────────

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}

output "efs_csi_role_arn" {
  value = var.enable_efs ? aws_iam_role.efs_csi[0].arn : null
}

output "cluster_autoscaler_role_arn" {
  value = var.enable_cluster_autoscaler ? aws_iam_role.cas[0].arn : null
}
