# ── S3 Bucket for WAL Archiving ───────────────────────────────────
resource "aws_s3_bucket" "wal" {
  bucket        = "${var.cluster_name}-taskflow-wal-${var.environment}"
  force_destroy = true

  tags = {
    Name        = "${var.cluster_name}-taskflow-wal"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "wal" {
  bucket = aws_s3_bucket.wal.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "wal" {
  bucket = aws_s3_bucket.wal.id

  rule {
    id     = "expire-old-wal"
    status = "Enabled"

    expiration {
      days = var.wal_retention_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wal" {
  bucket = aws_s3_bucket.wal.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "wal" {
  bucket                  = aws_s3_bucket.wal.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM Policy for CNPG S3 Access ────────────────────────────────
resource "aws_iam_policy" "cnpg_s3" {
  name        = "${var.cluster_name}-cnpg-s3-policy"
  description = "Allow CNPG to archive WAL to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.wal.arn,
          "${aws_s3_bucket.wal.arn}/*"
        ]
      }
    ]
  })
}

# ── IRSA Role for CNPG ───────────────────────────────────────────
resource "aws_iam_role" "cnpg" {
  name = "${var.cluster_name}-${var.environment}-cnpg-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.db_namespace}:postgres"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cnpg_s3" {
  role       = aws_iam_role.cnpg.name
  policy_arn = aws_iam_policy.cnpg_s3.arn
}

# ── Install CNPG Operator via Helm ───────────────────────────────
resource "helm_release" "cnpg_operator" {
  name             = "cnpg"
  repository       = "https://cloudnative-pg.github.io/charts"
  chart            = "cloudnative-pg"
  namespace        = "cnpg-system"
  create_namespace = true
  version          = "0.22.0"

  wait = true
  atomic           = true
  cleanup_on_fail  = true
  replace          = true
  
  lifecycle {
    ignore_changes = all
  }
  provisioner "local-exec" {
    when    = destroy
    command = "kubectl delete crd -l app.kubernetes.io/name=cloudnative-pg --ignore-not-found"
  }
}

# ── CNPG Cluster Manifest ─────────────────────────────────────────
resource "null_resource" "cnpg_cluster" {
  depends_on = [helm_release.cnpg_operator]

  triggers = {
    cluster_name   = var.cluster_name
    instances      = var.postgres_instances
    storage_size   = var.storage_size
    s3_bucket      = aws_s3_bucket.wal.bucket
    irsa_role_arn  = aws_iam_role.cnpg.arn
  }

  provisioner "local-exec" {
    command = <<-EOF
      kubectl apply -f - <<YAML
      apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      metadata:
        name: postgres
        namespace: ${var.db_namespace}
      spec:
        instances: ${var.postgres_instances}
        imageName: ghcr.io/cloudnative-pg/postgresql:16
        serviceAccountTemplate:
          metadata:
            annotations:
              eks.amazonaws.com/role-arn: ${aws_iam_role.cnpg.arn}
        storage:
          size: ${var.storage_size}
          storageClass: gp2
        bootstrap:
          initdb:
            database: taskflow
            owner: taskflow
            secret:
              name: ${var.db_secret_name}
        backup:
          barmanObjectStore:
            destinationPath: s3://${aws_s3_bucket.wal.bucket}/postgres
            s3Credentials:
              inheritFromIAMRole: true
            wal:
              compression: gzip
            data:
              compression: gzip
          retentionPolicy: "${var.wal_retention_days}d"
      YAML
    EOF
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOF
      kubectl delete cluster postgres -n ${self.triggers.db_namespace} --ignore-not-found
      kubectl delete pvc -l cnpg.io/cluster=postgres -n ${self.triggers.db_namespace} --ignore-not-found
      kubectl delete pvc postgres-1 -n ${self.triggers.db_namespace} --ignore-not-found
    EOF
  }

  lifecycle {
    ignore_changes = all
  }
}

# ── Scheduled Backup ─────────────────────────────────────────────
resource "null_resource" "cnpg_scheduled_backup" {
  depends_on = [null_resource.cnpg_cluster]

  triggers = {
    schedule = var.backup_schedule
  }

  provisioner "local-exec" {
    command = <<-EOF
      kubectl apply -f - <<YAML
      apiVersion: postgresql.cnpg.io/v1
      kind: ScheduledBackup
      metadata:
        name: postgres-backup
        namespace: ${var.db_namespace}
      spec:
        schedule: "${var.backup_schedule}"
        backupOwnerReference: self
        cluster:
          name: postgres
      YAML
    EOF
  }
    lifecycle {
        ignore_changes = all
    }
}