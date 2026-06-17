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
# IRSA — AWS LOAD BALANCER CONTROLLER
# ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lbc_trust" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.lbc_trust.json
}

# Download once and commit to your repo:
#   mkdir -p policies
#   curl -o policies/lbc-iam-policy.json \
#     https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
resource "aws_iam_policy" "lbc" {
  name        = "${var.cluster_name}-lbc-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.root}/../../src/policies/lbc-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

# ─────────────────────────────────────────────────────────────
# KUBERNETES SERVICE ACCOUNT (IRSA-annotated)
# ─────────────────────────────────────────────────────────────

resource "kubernetes_service_account_v1" "lbc" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.lbc.arn
    }

    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lbc]
}

# ─────────────────────────────────────────────────────────────
# HELM — AWS LOAD BALANCER CONTROLLER
# ─────────────────────────────────────────────────────────────

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_helm_version

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.aws_region
      vpcId       = var.vpc_id
      replicaCount = 2

      serviceAccount = {
        create = false
        name   = kubernetes_service_account_v1.lbc.metadata[0].name
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }

      affinity = {
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 100
              podAffinityTerm = {
                topologyKey = "kubernetes.io/hostname"
                labelSelector = {
                  matchExpressions = [
                    {
                      key      = "app.kubernetes.io/name"
                      operator = "In"
                      values   = ["aws-load-balancer-controller"]
                    }
                  ]
                }
              }
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    kubernetes_service_account_v1.lbc,
    aws_iam_role_policy_attachment.lbc,
  ]
}