locals {
  # Support either split (pm_api_token_id + pm_api_token_secret) or full "USER@REALM!TOKENID=UUID" in pm_api_token_id
  proxmox_api_token = strcontains(trimspace(var.pm_api_token_id), "=") ? trimspace(var.pm_api_token_id) : "${trimspace(var.pm_api_token_id)}=${trimspace(var.pm_api_token_secret)}"
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = local.proxmox_api_token
  insecure  = var.pm_tls_insecure
}

provider "talos" {}

provider "kubernetes" {
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
}
