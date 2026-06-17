resource "helm_release" "kube_prometheus_stack" {
  name       = "${var.cluster_name}-${var.environment}-kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "observability"
  version    = "67.0.0"

  create_namespace = true
  atomic = true
  cleanup_on_fail = true
  
  lifecycle {
    ignore_changes = all
  }
  
  values = [yamlencode({
    grafana = {
      enabled        = true
      adminPassword  = var.grafana_admin_password
    }

    prometheus = {
      prometheusSpec = {
        retention = "7d"
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp2" 
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = { storage = "10Gi" }
              }
            }
          }
        }
      }
    }

    tolerations = [
      { key = "type", operator = "Exists", effect = "NoSchedule" }
    ]
  })]
}