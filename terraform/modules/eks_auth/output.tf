output "admin_cluster_role_name" {
  value = kubernetes_cluster_role_v1.admin.metadata[0].name
}

output "developer_namespace_roles" {
  value = [for ns in var.developer_namespaces : ns]
}