resource "helm_release" "taskflow" {
  name       = "taskflow"
  chart      = "${path.module}/../../src/k8s/helm/taskflow"
  namespace  = var.namespace

  create_namespace = false

  values = [
    file("${path.module}/../../src/k8s/values/${var.env}/values.yaml")
  ]

  # 🔥 Important for stability
  timeout          = 600
  atomic           = true
  cleanup_on_fail  = true
  dependency_update = true
}