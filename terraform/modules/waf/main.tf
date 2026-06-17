resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project_name}-${var.env}-waf"
  scope       = "REGIONAL"   # Use CLOUDFRONT for CloudFront distributions
  description = "WAF Web ACL for ${var.project_name} ${var.env}"

  default_action {
    allow {}
  }

  # ── Rule 1: AWS Managed — Core rule set (OWASP Top 10) ──────────────────
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}   # Use count {} to test in shadow mode before enforcing
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 2: AWS Managed — Known bad inputs (SQLi, XSS, log4j) ───────────
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 3: AWS Managed — Amazon IP reputation list ─────────────────────
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-IPReputation"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 4: Rate limiting ────────────────────────────────────────────────
  rule {
    name     = "RateLimitPerIP"
    priority = 40

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 5: IP allowlist (optional — only created if CIDRs are provided) ─
  dynamic "rule" {
    for_each = length(var.allowed_ip_cidrs) > 0 ? [1] : []

    content {
      name     = "AllowListedIPs"
      priority = 5   # Evaluated first — allowlisted IPs bypass all other rules

      action {
        allow {}
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.allowlist[0].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.project_name}-AllowList"
        sampled_requests_enabled   = false
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-WebACL"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-waf"
    Environment = var.env
  })
}

# ── IP Set for allowlist (only created when allowed_ip_cidrs is non-empty) ──
resource "aws_wafv2_ip_set" "allowlist" {
  count = length(var.allowed_ip_cidrs) > 0 ? 1 : 0

  name               = "${var.project_name}-${var.env}-allowlist"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = var.allowed_ip_cidrs

  tags = var.tags
}

# ── Associate Web ACL with ALB ───────────────────────────────────────────────
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
