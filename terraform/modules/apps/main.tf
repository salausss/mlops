data "aws_caller_identity" "current" {}

# ---------------- DynamoDB: conversation history ----------------
resource "aws_dynamodb_table" "conversations" {
  name         = "${var.project_name}-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "ORDERS_TABLE" {
  name         = "ORDERS_TABLE"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"
  attribute {
    name = "order_id"
    type = "S"
  }
}

# ---------------- IRSA: IAM role assumable only by this ServiceAccount ----------------
resource "aws_iam_role" "irsa" {
  name = "${var.project_name}-${var.environment}-bedrock-irsa-role"

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
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "irsa" {
  name = "${var.project_name}-irsa-policy"
  role = aws_iam_role.irsa.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:Retrieve",
          "bedrock:InvokeModel",
          "bedrock:Converse"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.conversations.arn
      }
    ]
  })
}