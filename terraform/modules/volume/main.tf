# ── EFS Filesystem ────────────────────────────────────────────────
resource "aws_efs_file_system" "this" {
  creation_token   = "${var.cluster_name}-${var.environment}-efs"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = true
}

# ── Mount targets — one per subnet (one per AZ) ───────────────────
resource "aws_efs_mount_target" "this" {
  for_each = toset(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value  
  security_groups = [aws_security_group.efs.id]
}

# ── Security group — allow NFS from node security group ──────────
resource "aws_security_group" "efs" {
  name        = "${var.cluster_name}-${var.environment}-efs-sg"
  description = "Allow NFS from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-efs-sg"
  }
}

# ── Kubernetes StorageClass via Terraform ─────────────────────────
resource "kubernetes_storage_class_v1" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.this.id   # auto-injected, no manual copy
    directoryPerms   = "700"
    gidRangeStart    = "1000"
    gidRangeEnd      = "2000"
    basePath         = "/taskflow"
    #kmsKeyId         = var.kms_key_arn
  }

  depends_on = [aws_efs_mount_target.this]
}


# ── EBS gp2 with Retain (for Postgres StatefulSet) ───────────────
resource "kubernetes_storage_class_v1" "gp2_retain" {
  metadata {
    name = "gp2-retain"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"   # waits for pod scheduling, picks correct AZ
  allow_volume_expansion = true

  parameters = {
    type      = "gp2"
    encrypted = "true"
    #kmsKeyId  = var.kms_key_arn                     
}
}