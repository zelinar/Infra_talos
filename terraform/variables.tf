# ==============================================================================
# Proxmox Connection Variables
# ==============================================================================
variable "pm_api_url" {
  description = "Proxmox VE API endpoint URL (e.g. https://10.10.20.20:8006)"
  type        = string
  default     = "https://10.10.20.20:8006"
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID in the format USER@REALM!TOKENID (e.g. terraform@pve!terraform-token)"
  type        = string
  default     = "terraform@pve!terraform-token"

  validation {
    condition     = can(regex("^[a-zA-Z0-9\\-_\\.]+@[a-zA-Z0-9\\-_]+![a-zA-Z0-9\\-_]+(=[0-9a-fA-F-]{36})?$", trimspace(var.pm_api_token_id)))
    error_message = "pm_api_token_id must be in the format 'USER@REALM!TOKENID' (for example: 'terraform@pve!terraform-token' or 'root@pam!root-token')."
  }
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret UUID (e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  type        = string
  sensitive   = true

  validation {
    condition     = strcontains(trimspace(var.pm_api_token_id), "=") || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", trimspace(var.pm_api_token_secret)))
    error_message = "pm_api_token_secret must be a valid UUID (format: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')."
  }
}

variable "pm_tls_insecure" {
  description = "Skip TLS verification when connecting to Proxmox API"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Default Proxmox node name where VMs and ISOs will be placed"
  type        = string
  default     = "homelab-server"
}

variable "proxmox_iso_datastore" {
  description = "Proxmox datastore ID for storing the Talos ISO image"
  type        = string
  default     = "local"
}

variable "proxmox_vm_datastore" {
  description = "Proxmox datastore ID for VM disks"
  type        = string
  default     = "VM-storage"
}

# ==============================================================================
# Talos & Kubernetes Version Variables
# ==============================================================================
variable "talos_version" {
  description = "Talos Linux version to deploy (from Talos Image Factory)"
  type        = string
  default     = "v1.9.4"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy on Talos"
  type        = string
  default     = "1.32.2"
}

variable "talos_system_extensions" {
  description = "Official Talos system extensions to bake into the factory image (qemu-guest-agent for Proxmox, iscsi-tools & util-linux-tools for Longhorn)"
  type        = list(string)
  default = [
    "siderolabs/qemu-guest-agent",
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
  ]
}

variable "enable_nvidia_gpu" {
  description = "Include NVIDIA GPU drivers and NVIDIA Container Toolkit in the Talos Image Factory schematic"
  type        = bool
  default     = true
}

variable "nvidia_driver_branch" {
  description = "Talos NVIDIA driver extension variant: 'lts' (proprietary 535.x LTS required for Pascal/Quadro P620 GP107), 'production' (proprietary 550.x), or 'open-production' (open kernel modules for Turing+)"
  type        = string
  default     = "lts"

  validation {
    condition     = contains(["lts", "production", "open-production"], var.nvidia_driver_branch)
    error_message = "nvidia_driver_branch must be one of: 'lts', 'production', or 'open-production'."
  }
}

variable "download_talos_iso" {
  description = "Whether Terraform should automatically download the Talos Factory ISO onto Proxmox"
  type        = bool
  default     = true
}

variable "existing_talos_iso_file_id" {
  description = "If download_talos_iso is false, specify the existing Proxmox ISO file_id (e.g. local:iso/talos-nocloud-amd64.iso)"
  type        = string
  default     = ""
}

# ==============================================================================
# Cluster & Network Variables
# ==============================================================================
variable "cluster_name" {
  description = "Name of the Talos Kubernetes cluster"
  type        = string
  default     = "homelab-talos"
}

variable "cluster_vip" {
  description = "Optional Control Plane Virtual IP (VIP) managed natively by Talos for HA. Leave empty to use the primary control plane node IP directly."
  type        = string
  default     = ""
}

variable "network_bridge" {
  description = "Proxmox network bridge for cluster VMs"
  type        = string
  default     = "vmbr0"
}

variable "network_cidr_prefix" {
  description = "Subnet CIDR prefix length (e.g. 24 for /24)"
  type        = number
  default     = 24
}

variable "network_gateway" {
  description = "Default network gateway IPv4 address"
  type        = string
  default     = "10.10.20.1"
}

variable "dns_servers" {
  description = "DNS servers configured on Talos nodes"
  type        = list(string)
  default     = ["10.10.20.1", "1.1.1.1", "8.8.8.8"]
}

variable "pod_subnet" {
  description = "RFC1918 CIDR range for Kubernetes Pods"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_subnet" {
  description = "RFC1918 CIDR range for Kubernetes Services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "cni_provider" {
  description = "CNI provider to use: 'cilium' (recommended, replaces kube-proxy) or 'flannel' (Talos built-in default)"
  type        = string
  default     = "cilium"
  validation {
    condition     = contains(["cilium", "flannel"], var.cni_provider)
    error_message = "cni_provider must be either 'cilium' or 'flannel'."
  }
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.17.1"
}

variable "allow_scheduling_on_control_planes" {
  description = "Allow workload pods to schedule on control plane nodes"
  type        = bool
  default     = false
}

# ==============================================================================
# Layer 2–4: Platform Domain, Networking, TLS & GitOps Variables
# ==============================================================================
variable "base_domain" {
  description = "Base domain used across the platform for wildcard TLS certificates and service Ingresses (e.g. internal.cloud -> *.internal.cloud)"
  type        = string
  default     = "internal.cloud"
}

variable "cluster_environment" {
  description = "Environment label attached to cluster telemetry (e.g. homelab, prod, staging)"
  type        = string
  default     = "homelab"
}

variable "cluster_region" {
  description = "Region/location label attached to cluster telemetry (e.g. onprem, eu-central)"
  type        = string
  default     = "onprem"
}

variable "cluster_owner" {
  description = "Owner/team label attached to cluster telemetry"
  type        = string
  default     = "homelab"
}

variable "metallb_ip_pool_start" {
  description = "Start IPv4 address for the MetalLB L2 LoadBalancer IP pool"
  type        = string
  default     = "10.10.20.125"
}

variable "metallb_ip_pool_end" {
  description = "End IPv4 address for the MetalLB L2 LoadBalancer IP pool"
  type        = string
  default     = "10.10.20.129"
}

variable "traefik_lb_ip" {
  description = "Static LoadBalancer IPv4 address from the MetalLB pool assigned to Traefik Ingress Controller (defaults to metallb_ip_pool_start when empty)"
  type        = string
  default     = ""
}

variable "tls_mode" {
  description = "Platform TLS mode: 'internal-ca' (cluster Root CA) or 'letsencrypt' (ACME DNS-01 via Cloudflare)"
  type        = string
  default     = "internal-ca"

  validation {
    condition     = contains(["internal-ca", "letsencrypt"], var.tls_mode)
    error_message = "tls_mode must be either 'internal-ca' or 'letsencrypt'."
  }
}

variable "tls_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer used for signing platform certificates"
  type        = string
  default     = "homelab-ca-issuer"
}

variable "tls_ca_secret_name" {
  description = "Name of the Kubernetes Secret in cert-manager namespace holding the Root CA keypair (used when tls_mode = 'internal-ca')"
  type        = string
  default     = "homelab-ca-secret"
}

variable "tls_wildcard_secret_name" {
  description = "Name of the wildcard TLS Secret distributed across ingress namespaces"
  type        = string
  default     = "wildcard-homelab-secret"
}

variable "acme_email" {
  description = "Email address for Let's Encrypt ACME registration and expiry notifications (used when tls_mode = 'letsencrypt')"
  type        = string
  default     = "admin@internal.cloud"
}

variable "acme_server" {
  description = "ACME directory URL for Let's Encrypt (use https://acme-staging-v02.api.letsencrypt.org/directory for testing)"
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_cloudflare_api_token" {
  description = "Cloudflare API Token with Zone:DNS:Edit permissions for ACME DNS-01 wildcard validation (used when tls_mode = 'letsencrypt')"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vault_kv_path" {
  description = "Vault KV v2 mount path used for platform secrets"
  type        = string
  default     = "internal"
}

variable "vault_cluster_secret_store" {
  description = "Name of the External Secrets Operator ClusterSecretStore backed by Vault"
  type        = string
  default     = "vault-homelab"
}

variable "grafana_admin_user" {
  description = "Initial Grafana administrator username seeded into Vault"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Initial Grafana administrator password seeded into Vault"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "alloy_active_token" {
  description = "Bearer token seeded into Vault for Grafana Alloy -> VMAuth collection authentication"
  type        = string
  default     = "homelab-alloy-collect-token-active"
  sensitive   = true
}

variable "victoria_active_token" {
  description = "Bearer token seeded into Vault for VMAgent/VLAgent/VMAlert -> VMAuth ingestion authentication"
  type        = string
  default     = "homelab-victoria-ingest-token-active"
  sensitive   = true
}

variable "postgres_app_user" {
  description = "Application PostgreSQL username seeded into Vault for CloudNativePG clusters"
  type        = string
  default     = "appuser"
}

variable "postgres_app_password" {
  description = "Application PostgreSQL password seeded into Vault for CloudNativePG clusters"
  type        = string
  default     = "homelab-postgres-password"
  sensitive   = true
}

variable "longhorn_s3_backup_enabled" {
  description = "Enable S3 Backup Target and daily RecurringJob backups in Longhorn"
  type        = bool
  default     = false
}

variable "longhorn_s3_backup_target" {
  description = "Longhorn S3 backup target URI (e.g. s3://my-bucket@us-east-1/longhorn)"
  type        = string
  default     = ""
}

variable "longhorn_s3_endpoint" {
  description = "Optional custom S3 endpoint URL for MinIO / Cloudflare R2 / Backblaze B2 (leave empty for AWS S3)"
  type        = string
  default     = ""
}

variable "longhorn_s3_access_key" {
  description = "S3 Access Key ID seeded into Vault for Longhorn backups"
  type        = string
  default     = ""
  sensitive   = true
}

variable "longhorn_s3_secret_key" {
  description = "S3 Secret Access Key seeded into Vault for Longhorn backups"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_argocd" {
  description = "Deploy ArgoCD onto the cluster via Helm"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart from https://argoproj.github.io/argo-helm"
  type        = string
  default     = "9.4.17"
}

variable "argocd_domain" {
  description = "FQDN for ArgoCD UI Ingress (leave empty to default to argocd.<base_domain>)"
  type        = string
  default     = ""
}

variable "argocd_ha_enabled" {
  description = "Enable Redis HA and multi-replica autoscaling for ArgoCD"
  type        = bool
  default     = false
}

variable "argocd_admin_password" {
  description = "Optional custom plaintext password for ArgoCD admin user (automatically bcrypt-hashed). Leave empty to use ArgoCD's auto-generated initial secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "gitops_repo_url" {
  description = "Git repository URL containing Helm charts / manifests for ArgoCD ApplicationSets"
  type        = string
  default     = "https://github.com/zelinar/Infra_talos.git"
}

variable "gitops_repo_revision" {
  description = "Git branch or tag tracked by ArgoCD ApplicationSets"
  type        = string
  default     = "main"
}

variable "gitops_core_services_path" {
  description = "Directory path inside gitops_repo_url for core cluster services"
  type        = string
  default     = "core_services"
}

variable "gitops_observability_path" {
  description = "Directory path inside gitops_repo_url for observability services"
  type        = string
  default     = "observability"
}

variable "gitops_workloads_path" {
  description = "Directory path inside gitops_repo_url for application & database workloads"
  type        = string
  default     = "workloads"
}

variable "enable_argocd_appsets" {
  description = "Deploy ArgoCD ApplicationSets (core-services & observability) automatically"
  type        = bool
  default     = true
}

variable "enable_workloads_appset" {
  description = "Deploy ArgoCD ApplicationSet for Wave 7 workloads (HA CloudNativePG PostgreSQL with pgvector & Local LLM Stack)"
  type        = bool
  default     = true
}

# ==============================================================================
# Node Definitions
# ==============================================================================
variable "nodes" {
  description = "Map of Talos cluster nodes (controlplane and worker)"
  type = map(object({
    role              = string                       # "controlplane" or "worker"
    ip                = string                       # Static IPv4 address
    vm_id             = optional(number)             # Optional explicit Proxmox VMID
    target_node       = optional(string)             # Optional override for Proxmox node name
    cores             = optional(number, 4)          # CPU cores
    sockets           = optional(number, 1)          # CPU sockets
    cpu_type          = optional(string, "host")     # "host" exposes AVX2/FMA instructions for hybrid LLM inference
    memory_mb         = optional(number, 8192)       # RAM in MB
    os_disk_size_gb   = optional(number, 50)         # OS disk (scsi0 / /dev/sda) in GB
    data_disk_size_gb = optional(number, 0)          # Optional dedicated Longhorn disk (scsi1 / /dev/sdb) in GB (0 = use OS disk)
    gpu_worker        = optional(bool, false)        # Label node as GPU worker (gpu.internal.cloud/nvidia=true)
    gpu_pci_devices   = optional(list(string), [])   # Proxmox PCIe IDs for GPU passthrough (e.g. ["0000:01:00", "0000:02:00"])
    onboot            = optional(bool, true)
  }))

  default = {
    "k8s-talos-cp-01" = {
      role              = "controlplane"
      ip                = "10.10.20.120"
      vm_id             = 210
      cores             = 4
      memory_mb         = 4096
      os_disk_size_gb   = 50
      data_disk_size_gb = 0
    }
    "k8s-talos-worker-01" = {
      role              = "worker"
      ip                = "10.10.20.121"
      vm_id             = 211
      cores             = 6
      memory_mb         = 16384
      os_disk_size_gb   = 100
      data_disk_size_gb = 0
      gpu_worker        = true
      gpu_pci_devices   = [] # Add your 2x Quadro P620 PCIe addresses here once plugged in, e.g. ["0000:01:00", "0000:02:00"]
    }
    "k8s-talos-worker-02" = {
      role              = "worker"
      ip                = "10.10.20.122"
      vm_id             = 212
      cores             = 4
      memory_mb         = 8192
      os_disk_size_gb   = 100
      data_disk_size_gb = 0
    }
    "k8s-talos-worker-03" = {
      role              = "worker"
      ip                = "10.10.20.123"
      vm_id             = 213
      cores             = 4
      memory_mb         = 8192
      os_disk_size_gb   = 100
      data_disk_size_gb = 0
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.nodes : contains(["controlplane", "worker"], v.role)
    ])
    error_message = "Each node's role must be either 'controlplane' or 'worker'."
  }

  validation {
    condition     = length([for k, v in var.nodes : k if v.role == "controlplane"]) >= 1
    error_message = "At least one node with role = 'controlplane' must be defined."
  }
}
