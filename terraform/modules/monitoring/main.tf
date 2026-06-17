terraform {
  required_providers {
      grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
      }
    }
  }

# ------------ IAM Role for Grafana ------------ #
resource "aws_iam_role" "grafana_role" {
  name = "${var.cluster_name}-${var.env}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "grafana.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "grafana_amp_access" {
  role       = aws_iam_role.grafana_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" # For simplicity, using admin access. In production, scope this down to only necessary permissions.
}

# ------------ OIDC details from EKS for ADOT Role ------------ #
data "aws_caller_identity" "current" {}

# ------------ ADOT Role & Policy for Prometheus remote write ------------ #
resource "aws_iam_role" "adot_role" {
  name = "${var.cluster_name}-${var.env}-adot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:observability:${var.cluster_name}-${var.env}-adot-collector-sa"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "adot_amp" {
  name = "${var.cluster_name}-${var.env}-adot-amp-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      #Resource = aws_prometheus_workspace.this.arn
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "adot_attach" {
  role       = aws_iam_role.adot_role.name
  policy_arn = aws_iam_policy.adot_amp.arn
}

# ------------ AWS Managed Grafana Workspace & Prometheus Workspace ------------ #
resource "aws_prometheus_workspace" "this" {
  alias = "${var.cluster_name}-${var.env}-amp"
}

provider "grafana" {
  url  = "https://${aws_grafana_workspace.this.endpoint}"
  auth = aws_grafana_workspace_api_key.key.key
}

resource "time_rotating" "grafana_key" {
  rotation_days = 7
}

resource "aws_grafana_workspace_api_key" "key" {
  provider     = aws.grafana
  key_name     = "${var.cluster_name}-${var.env}-terraform-grafana-key-${time_rotating.grafana_key.id}"
  key_role     = "ADMIN"
  seconds_to_live = 2592000 # 30 days in seconds
  workspace_id = aws_grafana_workspace.this.id
  lifecycle {
    create_before_destroy = true
    replace_triggered_by = [time_rotating.grafana_key]  # rotation trigger
  }
}

provider "aws" {
  alias  = "grafana"
  region = "us-east-1" # AMG is only available in us-east-1.
}

resource "aws_grafana_workspace" "this" {
  provider = aws.grafana 
  name                     = "${var.cluster_name}-${var.env}-grafana"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"] 
  permission_type          = "SERVICE_MANAGED"
  role_arn = aws_iam_role.grafana_role.arn
  region = "us-east-1" # Grafana is only available in us-east-1, but can query AMP in other regions
  data_sources = ["PROMETHEUS"]
}

resource "grafana_data_source" "amp" {
  type = "prometheus"
  name = "${var.cluster_name}-${var.env}-amp-datasource"
  url  = aws_prometheus_workspace.this.prometheus_endpoint

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigV4Auth     = true
    sigV4Region   = "ap-south-1"
    #sigV4AuthType = "workspace-iam-role"
    sigV4AuthType = "default"
  })
#  lifecycle {
#    ignore_changes = all
#  }
  depends_on = [aws_grafana_workspace_api_key.key]
}

# ------------ ADOT Collector Helm Chart for Prometheus Remote Write ------------ #
resource "helm_release" "adot" {
  name       = "adot-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = "observability"

  create_namespace = true
  atomic = true
  cleanup_on_fail = true
  #lifecycle {
  #  ignore_changes = all
  #}

  values = [
    yamlencode({
      mode = "daemonset"

      image = {
        repository = "public.ecr.aws/aws-observability/aws-otel-collector"
        tag        = "latest"
      }

      serviceAccount = {
        create = true
        name   = "${var.cluster_name}-${var.env}-adot-collector-sa"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.adot_role.arn
        }
      }
      tolerations = [
      {
        key      = "type"
        operator = "Exists"    # matches both "application" and "database" values
        effect   = "NoSchedule"
        }
      ]
      extraEnvs = [
        {
          name = "K8S_NODE_NAME"
          valueFrom = {
            fieldRef = { fieldPath = "spec.nodeName" }
          }
        }
      ]
      config = {
        extensions = {
          sigv4auth    = { region = var.region, service = "aps" }
          health_check = {}
        }

        receivers = {
          prometheus = {
            config = {
              scrape_configs = [
                {
                  job_name          = "kubernetes-nodes"
                  scheme            = "https"
                  bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
                  tls_config = {
                    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                    insecure_skip_verify = false
                  }
                  kubernetes_sd_configs = [{ role = "node" }]
                  relabel_configs = [
                    {
                      source_labels = ["__meta_kubernetes_node_name"]
                      action        = "keep"
                      regex         = "$K8S_NODE_NAME"
                    },
                    { target_label = "__address__", replacement = "kubernetes.default.svc:443" },
                    { source_labels = ["__meta_kubernetes_node_name"], regex = "(.+)", target_label = "__metrics_path__", replacement = "/api/v1/nodes/$1/proxy/metrics" },
                    { action = "labelmap", regex = "__meta_kubernetes_node_label_(.+)" }
                  ]
                },
                {
                  job_name          = "kubernetes-nodes-cadvisor"
                  scheme            = "https"
                  bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
                  tls_config = {
                    ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                    insecure_skip_verify = false
                  }
                  kubernetes_sd_configs = [{ role = "node" }]
                  relabel_configs = [
                    {
                      source_labels = ["__meta_kubernetes_node_name"]
                      action        = "keep"
                      regex         = "$K8S_NODE_NAME"
                    },
                    { target_label = "__address__", replacement = "kubernetes.default.svc:443" },
                    { source_labels = ["__meta_kubernetes_node_name"], regex = "(.+)", target_label = "__metrics_path__", replacement = "/api/v1/nodes/$1/proxy/metrics/cadvisor" },
                    { action = "labelmap", regex = "__meta_kubernetes_node_label_(.+)" }
                  ]
                },
                {
                  job_name              = "kubernetes-pods"
                  kubernetes_sd_configs = [{ role = "pod" }]
                  relabel_configs = [
                    { source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"], action = "keep", regex = "true" },
                    { source_labels = ["__address__"], action = "drop", regex = ".*:9443" },
                    { source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scheme"], action = "replace", target_label = "__scheme__", regex = "(https?)" },
                    { source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"], action = "replace", target_label = "__metrics_path__", regex = "(.+)" },
                    { source_labels = ["__address__", "__meta_kubernetes_pod_annotation_prometheus_io_port"], action = "replace", target_label = "__address__", regex = "([^:]+)(?::\\d+)?;(\\d+)", replacement = "$1:$2" },
                    { action = "labelmap", regex = "__meta_kubernetes_pod_label_(.+)" },
                    { source_labels = ["__meta_kubernetes_namespace"], target_label = "namespace" },
                    { source_labels = ["__meta_kubernetes_pod_name"], target_label = "pod" }
                  ]
                }
              ]
            }
          }
        }

        #define processors before referencing them ──
        processors = {
          batch = {
            timeout         = "30s"
            send_batch_size = 1000
          }
          memory_limiter = {
            check_interval         = "1s"
            limit_percentage       = 75
            spike_limit_percentage = 15
          }
        }

        exporters = {
          prometheusremotewrite = {
            endpoint = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
            auth = {
              authenticator = "sigv4auth"
            }
          }
        }

        service = {
          extensions = ["sigv4auth", "health_check"]
          pipelines = {
            metrics = {
              receivers  = ["prometheus"]
              processors = ["memory_limiter", "batch"]  
              exporters  = ["prometheusremotewrite"]
            }
          }
        }
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.adot_attach,
    kubernetes_cluster_role_binding_v1.adot
  ]
}

# ------------ clusterRole to scrap data from nodes and pods for ADOT ------------ #
resource "kubernetes_cluster_role_v1" "adot" {
  metadata {
    name = "${var.cluster_name}-${var.env}-adot-collector-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "nodes", "nodes/proxy", "services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions", "apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "adot" {
  metadata {
    name = "${var.cluster_name}-${var.env}-adot-collector-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.adot.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "${var.cluster_name}-${var.env}-adot-collector-sa"
    namespace = "observability"
  }
}

# ------- Metrics setup for HPA & VPA ------------------- #
resource "helm_release" "metrics_server" {
  name       = "${var.cluster_name}-${var.env}-metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"

  namespace        = "kube-system"
  create_namespace = false

  # Important for EKS / self-managed clusters
  values = [
    yamlencode({
      args = [
        "--kubelet-insecure-tls",
        "--kubelet-preferred-address-types=InternalIP"
      ]
    })
  ]
}