data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────
# 1. SECRETS DEFINITION
# ─────────────────────────────────────────────

# TaskFlow App Secret — JWT, API keys, etc.
resource "aws_secretsmanager_secret" "taskflow_app" {
  name                    = "${var.cluster_name}/${var.env}/taskflow/app"
  description             = "TaskFlow application secrets — JWT, API keys, third-party credentials"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-taskflow-app-secret"
    Namespace = var.app_namespace
  })
}

# Placeholder value — you will overwrite this from CLI after apply
resource "aws_secretsmanager_secret_version" "taskflow_app" {
  secret_id = aws_secretsmanager_secret.taskflow_app.id

  secret_string = jsonencode({
    JWT_SECRET       = "PLACEHOLDER_REPLACE_ME"
    API_KEY          = "PLACEHOLDER_REPLACE_ME"
    COGNITO_SECRET   = "PLACEHOLDER_REPLACE_ME"
    APP_ENCRYPTION_KEY = "PLACEHOLDER_REPLACE_ME"
    
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# TaskFlow DB Secret — database credentials
resource "aws_secretsmanager_secret" "taskflow_db" {
  name                    = "${var.cluster_name}/${var.env}/taskflow/db"
  description             = "TaskFlow database credentials with automatic rotation"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = "${var.cluster_name}-taskflow-db-secret"
    Namespace = var.db_namespace
  })
}

resource "aws_secretsmanager_secret_version" "taskflow_db" {
  secret_id = aws_secretsmanager_secret.taskflow_db.id

  secret_string = jsonencode({
    username = "PLACEHOLDER_REPLACE_ME"
    password = "PLACEHOLDER_REPLACE_ME"
    host     = "PLACEHOLDER_REPLACE_ME"
    port     = "5432"
    dbname   = "taskflow"
    REPLICATOR_PASSWORD = "PLACEHOLDER_REPLACE_ME"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ─────────────────────────────────────────────
# 2. SECRET ROTATION (DB credentials)
# ─────────────────────────────────────────────

resource "aws_secretsmanager_secret_rotation" "taskflow_db" {
  secret_id           = aws_secretsmanager_secret.taskflow_db.id
  rotation_lambda_arn = aws_lambda_function.secret_rotation.arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_permission.secrets_manager_invoke]
}

# ─────────────────────────────────────────────
# 3. ROTATION LAMBDA
# ─────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda" {
  name               = "${var.cluster_name}-${var.env}secret-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "rotation_lambda_policy" {
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage",
    ]
    resources = [aws_secretsmanager_secret.taskflow_db.arn]
  }

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name   = "${var.cluster_name}-${var.env}-secret-rotation-lambda-policy"
  role   = aws_iam_role.rotation_lambda.id
  policy = data.aws_iam_policy_document.rotation_lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Minimal rotation Lambda — rotates DB password, updates secret
# In production, replace with RDS-specific rotation template from AWS SAR
resource "aws_lambda_function" "secret_rotation" {
  function_name    = "${var.cluster_name}-${var.env}-secret-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.rotation_lambda.output_path
  source_code_hash = data.archive_file.rotation_lambda.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SECRET_ARN = aws_secretsmanager_secret.taskflow_db.arn
    }
  }

  tags = var.tags
}

data "archive_file" "rotation_lambda" {
  type        = "zip"
  output_path = "${path.module}/rotation_lambda.zip"

  source {
    content  = <<-EOF
      import boto3
      import json
      import os

      def handler(event, context):
          """
          Minimal rotation handler. Replace with full RDS rotation logic
          or use the AWS-provided rotation template from Serverless App Repository.
          
          Steps: createSecret → setSecret → testSecret → finishSecret
          """
          arn   = event["SecretId"]
          token = event["ClientRequestToken"]
          step  = event["Step"]

          client = boto3.client("secretsmanager")
          metadata = client.describe_secret(SecretId=arn)

          if not metadata.get("RotationEnabled"):
              raise ValueError(f"Rotation not enabled for secret {arn}")

          versions = metadata.get("VersionIdsToStages", {})
          if token not in versions:
              raise ValueError(f"Token {token} is not staged for rotation")

          if "AWSCURRENT" in versions[token]:
              return  # already current, nothing to do

          if step == "createSecret":
              _create_secret(client, arn, token)
          elif step == "setSecret":
              _set_secret(client, arn, token)
          elif step == "testSecret":
              _test_secret(client, arn, token)
          elif step == "finishSecret":
              _finish_secret(client, arn, token)
          else:
              raise ValueError(f"Unknown step: {step}")

      def _create_secret(client, arn, token):
          import string, secrets
          alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
          new_password = "".join(secrets.choice(alphabet) for _ in range(32))
          try:
              client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING")
          except client.exceptions.ResourceNotFoundException:
              current = json.loads(
                  client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
              )
              current["password"] = new_password
              client.put_secret_value(
                  SecretId=arn,
                  ClientRequestToken=token,
                  SecretString=json.dumps(current),
                  VersionStages=["AWSPENDING"],
              )

      def _set_secret(client, arn, token):
          # Hook: update your actual DB password here using psycopg2 / pymysql
          pass

      def _test_secret(client, arn, token):
          # Hook: verify the new password works against the DB
          pass

      def _finish_secret(client, arn, token):
          metadata = client.describe_secret(SecretId=arn)
          current_version = next(
              v for v, stages in metadata["VersionIdsToStages"].items()
              if "AWSCURRENT" in stages
          )
          client.update_secret_version_stage(
              SecretId=arn,
              VersionStage="AWSCURRENT",
              MoveToVersionId=token,
              RemoveFromVersionId=current_version,
          )
    EOF
    filename = "index.py"
  }
}

resource "aws_lambda_permission" "secrets_manager_invoke" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.taskflow_db.arn
}

# ─────────────────────────────────────────────
# 4. IRSA — IAM ROLES FOR SERVICE ACCOUNTS
# ─────────────────────────────────────────────

data "aws_eks_cluster" "primary" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.primary.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer       = replace(data.aws_eks_cluster.primary.identity[0].oidc[0].issuer, "https://", "")
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
}

# App namespace service account role
data "aws_iam_policy_document" "app_sa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.app_namespace}:${var.app_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_sa" {
  name               = "${var.cluster_name}-${var.env}-${var.app_namespace}-sa-role"
  assume_role_policy = data.aws_iam_policy_document.app_sa_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "app_sa_secrets_policy" {
  statement {
    sid    = "GetAppSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to ONLY the app secret & db secret as backend need DB access.
    resources = [aws_secretsmanager_secret.taskflow_app.arn, aws_secretsmanager_secret.taskflow_db.arn]
  }

  statement {
    sid    = "DecryptWithCMK"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "app_sa_secrets" {
  name   = "${var.cluster_name}-${var.env}-${var.app_namespace}-secrets-policy"
  role   = aws_iam_role.app_sa.id
  policy = data.aws_iam_policy_document.app_sa_secrets_policy.json
}

# DB namespace service account role
data "aws_iam_policy_document" "db_sa_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.db_namespace}:${var.db_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_sa" {
  name               = "${var.cluster_name}-${var.env}-${var.db_namespace}-sa-role"
  assume_role_policy = data.aws_iam_policy_document.db_sa_assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "db_sa_secrets_policy" {
  statement {
    sid    = "GetDBSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped to ONLY the DB secret — not app secrets
    resources = [aws_secretsmanager_secret.taskflow_db.arn]
  }

  statement {
    sid    = "DecryptWithCMK"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "db_sa_secrets" {
  name   = "${var.cluster_name}-${var.env}-${var.db_namespace}-secrets-policy"
  role   = aws_iam_role.db_sa.id
  policy = data.aws_iam_policy_document.db_sa_secrets_policy.json
}

# ─────────────────────────────────────────────
# 5. SECRETS STORE CSI DRIVER — HELM
# ─────────────────────────────────────────────

resource "helm_release" "secrets_store_csi_driver" {
  name             = "secrets-store-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart            = "secrets-store-csi-driver"
  namespace        = "kube-system"
  version          = "1.4.7"
  create_namespace = false

  values = [
    yamlencode({
      syncSecret = {
        enabled = true
      }
      enableSecretRotation = true
      rotationPollInterval = "2m"
    })
  ]
}

resource "helm_release" "aws_secrets_provider" {
  name             = "aws-secrets-provider"
  repository       = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart            = "secrets-store-csi-driver-provider-aws"
  namespace        = "kube-system"
  version          = "0.3.9"
  create_namespace = false

  depends_on = [helm_release.secrets_store_csi_driver]
}

# ─────────────────────────────────────────────
# 6. KUBERNETES SERVICE ACCOUNTS (with IRSA annotation)
# ─────────────────────────────────────────────

resource "kubernetes_service_account_v1" "taskflow_app" {
  metadata {
    name      = var.app_service_account
    namespace = var.app_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app_sa.arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_iam_role_policy.app_sa_secrets]
}

resource "kubernetes_service_account_v1" "taskflow_db" {
  metadata {
    name      = var.db_service_account
    namespace = var.db_namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.db_sa.arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_iam_role_policy.db_sa_secrets]
}

# ─────────────────────────────────────────────
# 7. SECRET PROVIDER CLASS MANIFESTS
# ─────────────────────────────────────────────
resource "null_resource" "secret_provider_classes" {
  triggers = {
    app_secret_name = aws_secretsmanager_secret.taskflow_app.name
    db_secret_name  = aws_secretsmanager_secret.taskflow_db.name
    app_namespace   = var.app_namespace
    db_namespace    = var.db_namespace
    region          = var.region
    cluster_name    = var.cluster_name
    manifest_hash   = sha256(join("", [
      var.app_namespace,
      var.db_namespace,
      var.region,
      aws_secretsmanager_secret.taskflow_app.name,
      aws_secretsmanager_secret.taskflow_db.name,
      "v3"
    ]))
  }

  provisioner "local-exec" {
    command = <<-SCRIPT
      aws eks update-kubeconfig --region ${var.region} --name ${var.cluster_name}

      cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: taskflow-app-secrets
  namespace: ${var.app_namespace}
spec:
  provider: aws
  parameters:
    region: ${var.region}
    objects: |
      - objectName: "${aws_secretsmanager_secret.taskflow_app.name}"
        objectType: secretsmanager
        jmesPath:
          - path: JWT_SECRET
            objectAlias: jwt_secret
          - path: API_KEY
            objectAlias: api_key
          - path: COGNITO_SECRET
            objectAlias: cognito_secret
          - path: APP_ENCRYPTION_KEY
            objectAlias: app_encryption_key

      - objectName: "${aws_secretsmanager_secret.taskflow_db.arn}"
        objectType: secretsmanager
        jmesPath:
          - path: password
            objectAlias: postgres_password
          - path: username
            objectAlias: postgres_user
          - path: dbname
            objectAlias: postgres_db
          - path: host
            objectAlias: postgres_host
          - path: port
            objectAlias: postgres_port
      
  secretObjects:
    - secretName: taskflow-app-secrets
      type: Opaque
      data:
        - objectName: jwt_secret
          key: JWT_SECRET
        - objectName: api_key
          key: API_KEY
        - objectName: cognito_secret
          key: COGNITO_SECRET
        - objectName: app_encryption_key
          key: APP_ENCRYPTION_KEY

    - secretName: taskflow-db-credentials
      type: Opaque
      data:
        - objectName: postgres_password
          key: POSTGRES_PASSWORD
        - objectName: postgres_user
          key: POSTGRES_USER
        - objectName: postgres_db
          key: POSTGRES_DB
        - objectName: postgres_host
          key: POSTGRES_HOST
        - objectName: postgres_port
          key: POSTGRES_PORT
EOF

cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: taskflow-db-secrets
  namespace: ${var.db_namespace}
spec:
  provider: aws
  parameters:
    region: ${var.region}
    objects: |
      - objectName: "${aws_secretsmanager_secret.taskflow_db.arn}"
        objectType: secretsmanager
        jmesPath:
          - path: password
            objectAlias: postgres_password
          - path: username
            objectAlias: postgres_user
          - path: dbname
            objectAlias: postgres_db
          - path: replicator_password
            objectAlias: replicator_password
  secretObjects:
    - secretName: taskflow-db-credentials
      type: Opaque
      data:
        - objectName: postgres_password
          key: POSTGRES_PASSWORD
        - objectName: postgres_user
          key: POSTGRES_USER
        - objectName: postgres_db
          key: POSTGRES_DB
        - objectName: replicator_password
          key: replicator_password
EOF
    SCRIPT
  }
}