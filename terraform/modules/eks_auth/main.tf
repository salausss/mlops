data "aws_caller_identity" "current" {}

# -------------------------------------------------------
# Admin IAM Role
# -------------------------------------------------------
resource "aws_iam_role" "eks_admin" {
  name = "${var.cluster_name}-${var.env}-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# -------------------------------------------------------
# Developer IAM Role
# -------------------------------------------------------
resource "aws_iam_role" "eks_developer" {
  name = "${var.cluster_name}-${var.env}-developer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# -------------------------------------------------------
# aws-auth ConfigMap
# -------------------------------------------------------
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = yamlencode([
  {
    rolearn  = var.node_group_role
    username = "system:node:{{EC2PrivateDNSName}}"
    groups   = ["system:bootstrappers", "system:nodes"]
  },
  {
    rolearn  = aws_iam_role.eks_admin.arn
    username = "eks-admin"
    groups   = [var.admin_group_name]
  },
  {
    rolearn  = aws_iam_role.eks_developer.arn
    username = "eks-developer"
    groups   = [var.developer_group_name]
  }
    ])

    mapUsers = yamlencode(concat(
      [
        for arn in var.admin_user_arns : {
          userarn  = arn
          username = split("/", arn)[1]
          groups   = [var.admin_group_name]
        }
      ],
      [
        for arn in var.developer_user_arns : {
          userarn  = arn
          username = split("/", arn)[1]
          groups   = [var.developer_group_name]
        }
      ]
    ))
  }
  }


# -------------------------------------------------------
# Admin ClusterRole + ClusterRoleBinding
# -------------------------------------------------------
resource "kubernetes_cluster_role_v1" "admin" {

  metadata {
    name = "eks-admin-role"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "admin" {

  metadata {
    name = "eks-admin-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.admin.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = var.admin_group_name        # ← same variable, guaranteed match
    api_group = "rbac.authorization.k8s.io"
  }
}

# -------------------------------------------------------
# Creating Namespaces
# -------------------------------------------------------
resource "kubernetes_namespace_v1" "admin_developer" {
  for_each = toset(var.developer_namespaces)

  metadata {
    name = each.key
  }
}

# -------------------------------------------------------
# Developer ClusterRole (read-only cluster-wide)
# -------------------------------------------------------
resource "kubernetes_cluster_role_v1" "developer_readonly" {
  metadata {
    name = "eks-developer-readonly"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "developer_readonly" {
  metadata {
    name = "eks-developer-readonly-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.developer_readonly.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = var.developer_group_name    # ← same variable, guaranteed match
    api_group = "rbac.authorization.k8s.io"
  }
}

# -------------------------------------------------------
# Developer Role (namespace-scoped)
# -------------------------------------------------------
resource "kubernetes_role_v1" "developer" {
  for_each = toset(var.developer_namespaces)

  metadata {
    name      = "eks-developer-role"
    namespace = each.key
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/exec", "pods/portforward"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "developer" {
  for_each = toset(var.developer_namespaces)

  metadata {
    name      = "eks-developer-binding"
    namespace = each.key
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.developer[each.key].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = var.developer_group_name    # ← same variable, guaranteed match
    api_group = "rbac.authorization.k8s.io"
  }
}

