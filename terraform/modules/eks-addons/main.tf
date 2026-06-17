# ─────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "primary" {
  name = var.cluster_name
}

# ─────────────────────────────────────────────────────────────
# OIDC PROVIDER
# ─────────────────────────────────────────────────────────────

#resource "aws_iam_openid_connect_provider" "eks" {
#  url             = data.aws_eks_cluster.primary.identity[0].oidc[0].issuer
#  client_id_list  = ["sts.amazonaws.com"]
#  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
#}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.primary.identity[0].oidc[0].issuer
}


# ─────────────────────────────────────────────────────────────
# LOCALS
# ─────────────────────────────────────────────────────────────

locals {
  oidc_issuer       = replace(data.aws_eks_cluster.primary.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
}

# ─────────────────────────────────────────────────────────────
# EKS MANAGED ADDONS
# ─────────────────────────────────────────────────────────────

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = var.cluster_name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_addon.vpc_cni]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_addon.vpc_cni]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_addon.vpc_cni,
  ]
}

resource "aws_eks_addon" "efs_csi_driver" {
  count                       = var.enable_efs ? 1 : 0
  cluster_name                = var.cluster_name
  addon_name                  = "aws-efs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  service_account_role_arn    = aws_iam_role.efs_csi[0].arn
  depends_on = [
    aws_iam_role_policy_attachment.efs_csi,
    aws_eks_addon.vpc_cni,
  ]
}


# ─────────────────────────────────────────────────────────────
# IRSA — EBS CSI DRIVER
# ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# ─────────────────────────────────────────────────────────────
# IRSA — EFS CSI DRIVER (conditional)
# ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "efs_csi_trust" {
  count = var.enable_efs ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi" {
  count              = var.enable_efs ? 1 : 0
  name               = "${var.cluster_name}-efs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_trust[0].json
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count      = var.enable_efs ? 1 : 0
  role       = aws_iam_role.efs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# ─────────────────────────────────────────────────────────────
# IRSA — CLUSTER AUTOSCALER (conditional)
# ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cas_trust" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cas" {
  count              = var.enable_cluster_autoscaler ? 1 : 0
  name               = "${var.cluster_name}-cas-role"
  assume_role_policy = data.aws_iam_policy_document.cas_trust[0].json
}

resource "aws_iam_role_policy" "cas_inline" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cas-inline"
  role  = aws_iam_role.cas[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      }
    ]
  })
}