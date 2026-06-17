resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_iam_role" "node_group_role" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Required for nodes to join the cluster
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

# Required for IPv4 networking
resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

# Required to pull images from ECR
resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# Creating EKS Cluster 

resource "aws_eks_cluster" "primary" {
  name    = var.cluster_name
  version = var.cluster_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidr
  }

  # CORRECTED: service_ipv4_cidr is now nested inside this block
  kubernetes_network_config {
    service_ipv4_cidr = var.service_ipv4_cidr_block
    #service_ipv4_cidr = data.aws_vpc.existing_vpc.cidr_block
  }
  
  access_config {
    # This enables the API while keeping your current ConfigMap working
    authentication_mode = "CONFIG_MAP" 
  
    # This ensures the IAM user/role running Terraform doesn't lose admin access
    bootstrap_cluster_creator_admin_permissions = true 
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = var.kms_key_arn
    }
  }
}

# Data source to get the OIDC provider's certificate for thumbprint
data "tls_certificate" "eks" {
  url = aws_eks_cluster.primary.identity[0].oidc[0].issuer
}

# Create the IAM OIDC Identity Provider
resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.primary.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.cluster_name}-oidc-provider"
    Environment = "EKS" # Or use a variable for environment
  }
}


data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# System Node Group (For CoreDNS, LBC, etc.)
resource "aws_eks_node_group" "system_node" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = "system-pool"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.cluster_pool_machine_type]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  # Labels are good for organization, but we leave Taints empty
  labels = {
    "node-type" = "system"
  }

  ami_type   = var.ami_type
  depends_on = [aws_eks_cluster.primary]
}

# Application Node Group
resource "aws_eks_node_group" "application_node" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = var.application_node_name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.application_pool_machine_type]
  disk_size       = var.application_pool_disk_size_gb

  scaling_config {
    desired_size = var.application_pool_node_count
    min_size     = var.application_pool_min_node_count
    max_size     = var.application_pool_max_node_count
  }

  update_config {
    max_unavailable = var.application_pool_max_unavailable
  }

  taint {
    key    = "type"
    value  = "application"
    effect = "NO_SCHEDULE"
  }
  labels = {
    "node-type" = "application"
  }
  ami_type = var.ami_type

  depends_on = [aws_eks_cluster.primary]
}

# Database Node Group
resource "aws_eks_node_group" "database_node" {
  cluster_name    = aws_eks_cluster.primary.name
  node_group_name = var.database_node_name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.database_pool_machine_type]
  disk_size       = var.database_pool_disk_size_gb

  scaling_config {
    desired_size = var.database_pool_node_count
    min_size     = var.database_pool_min_node_count
    max_size     = var.database_pool_max_node_count
  }

  update_config {
    max_unavailable = var.database_pool_max_unavailable
  }

  taint {
    key    = "type"
    value  = "database"
    effect = "NO_SCHEDULE"
  }
  labels = {
    "type" = "database"
  }
  ami_type = var.ami_type

  depends_on = [aws_eks_cluster.primary]
}

resource "aws_security_group_rule" "allow_manual_vpc_443" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["172.31.0.0/16"] 
  security_group_id = aws_eks_cluster.primary.vpc_config[0].cluster_security_group_id
  description       = "Allow HTTPS from EC2 to EKS"
}

