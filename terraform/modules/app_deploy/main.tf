#--------- Create ArgoCD --------------------#
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"

  namespace        = "argocd"
  create_namespace = true
  wait             = true        # wait for all pods to be Ready
  wait_for_jobs    = true
  skip_crds = false

  atomic           = true
  cleanup_on_fail  = true
  replace          = true

  values = [<<EOF
  installCRDs: true
  server:
    service:
       type: ClusterIP
EOF
  ]

  timeout = 600
}

# Give the CRDs a moment to fully register in the API server
resource "time_sleep" "wait_for_argocd_crds" {
  depends_on      = [helm_release.argocd]
  create_duration = "30s"
}

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"

  namespace        = "kube-system"
  create_namespace = false
}

#--------- Create initialApplication once and Managed through ArgoCD -------------------#

resource "null_resource" "taskflow_app" {
  depends_on = [time_sleep.wait_for_argocd_crds]

  triggers = {
    manifest_hash = sha256(local.taskflow_manifest)
  }

  provisioner "local-exec" {
    command = <<EOT
      cat <<'MANIFEST' | kubectl apply -f -
${local.taskflow_manifest}
MANIFEST
    EOT
  }
  lifecycle {
    ignore_changes = all
  }
}

locals {
  taskflow_manifest = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: taskflow
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/salausss/three-tier-application
    targetRevision: main
    path: src/k8s/helm/taskflow
    helm:
      valueFiles:
        - ../../values/dev/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: app
YAML
}

data "aws_lb" "taskflow" {
  tags = {
    "ingress.k8s.aws/stack" = "app/taskflow-ingress"  # <namespace>/<ingress-name>
  }
  depends_on = [null_resource.taskflow_app]
}