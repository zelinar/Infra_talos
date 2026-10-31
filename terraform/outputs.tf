# ==============================================================================
# Outputs
# ==============================================================================

output "cluster_name" {
  description = "Name of the Talos Kubernetes cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = local.cluster_endpoint
}

output "talos_schematic_id" {
  description = "Generated Talos Image Factory schematic ID (includes qemu-guest-agent, iscsi-tools, util-linux-tools)"
  value       = talos_image_factory_schematic.this.id
}

output "talos_factory_iso_url" {
  description = "URL of the Talos Factory NoCloud ISO image"
  value       = local.talos_factory_iso_url
}

output "talos_installer_image" {
  description = "Talos installer container image used for disk installation and upgrades"
  value       = local.talos_installer_image
}

output "node_ips" {
  description = "Map of cluster node names to their static IPv4 addresses and roles"
  value = {
    for k, v in var.nodes : k => {
      role = v.role
      ip   = v.ip
    }
  }
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = abspath(local_sensitive_file.kubeconfig.filename)
}

output "talosconfig_path" {
  description = "Path to the generated talosconfig file"
  value       = abspath(local_sensitive_file.talosconfig.filename)
}

output "kubeconfig_raw" {
  description = "Raw kubeconfig content"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig_raw" {
  description = "Raw talosconfig content"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "argocd_domain" {
  description = "Configured ArgoCD Ingress FQDN"
  value       = var.enable_argocd ? "https://${var.argocd_domain}" : null
}

output "argocd_initial_admin_password" {
  description = "ArgoCD admin password (retrieve with: terraform output -raw argocd_initial_admin_password)"
  value = var.enable_argocd ? (
    var.argocd_admin_password != "" ? var.argocd_admin_password : try(data.kubernetes_secret_v1.argocd_initial_admin[0].data["password"], "")
  ) : null
  sensitive = true
}

