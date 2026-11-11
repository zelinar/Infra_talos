# ==============================================================================
# Talos Machine Configuration, Bootstrap & Credentials
# ==============================================================================

locals {
  control_plane_nodes = {
    for k, v in var.nodes : k => v if v.role == "controlplane"
  }
  worker_nodes = {
    for k, v in var.nodes : k => v if v.role == "worker"
  }

  # Primary control plane node used for initial etcd bootstrap
  primary_control_plane_key = sort(keys(local.control_plane_nodes))[0]
  primary_control_plane_ip  = local.control_plane_nodes[local.primary_control_plane_key].ip

  # Use VIP if configured, otherwise primary control plane IP
  cluster_endpoint_ip = var.cluster_vip != "" ? var.cluster_vip : local.primary_control_plane_ip
  cluster_endpoint    = "https://${local.cluster_endpoint_ip}:6443"
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for k, v in local.control_plane_nodes : v.ip]
  nodes                = [for k, v in var.nodes : v.ip]
}

data "talos_machine_configuration" "controlplane" {
  for_each = local.control_plane_nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    templatefile("${path.module}/templates/controlplane-patch.yaml.tftpl", {
      hostname                           = each.key
      installer_image                    = local.talos_installer_image
      ip                                 = each.value.ip
      cidr_prefix                        = var.network_cidr_prefix
      gateway                            = var.network_gateway
      dns_servers                        = var.dns_servers
      cluster_vip                        = var.cluster_vip
      pod_subnet                         = var.pod_subnet
      service_subnet                     = var.service_subnet
      cni_provider                       = var.cni_provider
      allow_scheduling_on_control_planes = var.allow_scheduling_on_control_planes
      has_data_disk                      = each.value.data_disk_size_gb > 0
    })
  ]
}

data "talos_machine_configuration" "worker" {
  for_each = local.worker_nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    templatefile("${path.module}/templates/worker-patch.yaml.tftpl", {
      hostname          = each.key
      installer_image   = (var.enable_nvidia_gpu && length(each.value.gpu_pci_devices) > 0) ? local.talos_gpu_installer_image : local.talos_installer_image
      ip                = each.value.ip
      cidr_prefix       = var.network_cidr_prefix
      gateway           = var.network_gateway
      dns_servers       = var.dns_servers
      pod_subnet        = var.pod_subnet
      service_subnet    = var.service_subnet
      has_data_disk     = each.value.data_disk_size_gb > 0
      enable_nvidia_gpu = var.enable_nvidia_gpu
      has_gpu           = length(each.value.gpu_pci_devices) > 0
      is_gpu_worker     = var.enable_nvidia_gpu && length(each.value.gpu_pci_devices) > 0
    })
  ]
}

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = local.control_plane_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane[each.key].machine_configuration
  node                        = each.value.ip

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_vm.talos_node[each.key]
    ]
  }

  depends_on = [
    proxmox_virtual_environment_vm.talos_node
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = local.worker_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.key].machine_configuration
  node                        = each.value.ip

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_vm.talos_node[each.key]
    ]
  }

  depends_on = [
    proxmox_virtual_environment_vm.talos_node
  ]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.primary_control_plane_ip

  lifecycle {
    replace_triggered_by = [
      talos_machine_configuration_apply.controlplane,
    ]
  }

  depends_on = [
    talos_machine_configuration_apply.controlplane
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.primary_control_plane_ip

  depends_on = [
    talos_machine_bootstrap.this
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/generated/kubeconfig"
  file_permission = "0600"
}

resource "local_sensitive_file" "talosconfig" {
  content         = data.talos_client_configuration.this.talos_config
  filename        = "${path.module}/generated/talosconfig"
  file_permission = "0600"
}

# Automatically upgrade existing GPU worker nodes to the Talos GPU schematic image
# (installs nonfree-kmod-nvidia-lts and nvidia-container-toolkit-lts without manual talosctl steps)
resource "terraform_data" "worker_gpu_schematic_upgrade" {
  for_each = {
    for k, v in local.worker_nodes : k => v
    if var.enable_nvidia_gpu && length(v.gpu_pci_devices) > 0
  }

  triggers_replace = [
    local.talos_gpu_installer_image,
    join(",", each.value.gpu_pci_devices),
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      BIN_DIR="${path.module}/.terraform/bin"
      TALOSCTL="$BIN_DIR/talosctl"
      if command -v talosctl >/dev/null 2>&1; then
        TALOSCTL="$(command -v talosctl)"
      elif [ ! -x "$TALOSCTL" ]; then
        echo "Downloading talosctl ${var.talos_version} to $TALOSCTL..."
        mkdir -p "$BIN_DIR"
        curl -fsSL -o "$TALOSCTL" "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/talosctl-linux-amd64"
        chmod +x "$TALOSCTL"
      fi

      echo "Waiting for Talos API on ${each.key} (${each.value.ip}:50000) to be reachable..."
      for i in $(seq 1 60); do
        if "$TALOSCTL" --talosconfig="${local_sensitive_file.talosconfig.filename}" version --nodes "${each.value.ip}" --endpoints "${local.primary_control_plane_ip}" >/dev/null 2>&1; then
          break
        fi
        sleep 3
      done

      echo "Upgrading GPU worker ${each.key} (${each.value.ip}) to Talos GPU schematic (${local.talos_gpu_installer_image})..."
      "$TALOSCTL" --talosconfig="${local_sensitive_file.talosconfig.filename}" upgrade \
        --nodes "${each.value.ip}" \
        --endpoints "${local.primary_control_plane_ip}" \
        --image "${local.talos_gpu_installer_image}" \
        --wait=true
    EOT
  }

  depends_on = [
    proxmox_virtual_environment_vm.talos_node,
    talos_machine_configuration_apply.worker,
    local_sensitive_file.talosconfig,
  ]
}

# Wait for all Talos nodes to finish disk install, reboot, and start etcd & kubelet
data "talos_cluster_health" "this" {
  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = [for k, v in local.control_plane_nodes : v.ip]
  worker_nodes           = [for k, v in local.worker_nodes : v.ip]
  endpoints              = data.talos_client_configuration.this.endpoints
  skip_kubernetes_checks = true

  timeouts = {
    read = "10m"
  }

  depends_on = [
    talos_machine_bootstrap.this,
    talos_machine_configuration_apply.controlplane,
    talos_machine_configuration_apply.worker,
    terraform_data.worker_gpu_schematic_upgrade,
  ]
}

# Wait until kube-apiserver (port 6443) is accepting connections before Helm runs
resource "terraform_data" "wait_for_k8s_api" {
  triggers_replace = [
    talos_cluster_kubeconfig.this.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Kubernetes API at ${local.cluster_endpoint}..."
      for i in $(seq 1 90); do
        if kubectl --kubeconfig="${local_sensitive_file.kubeconfig.filename}" get --raw=/livez >/dev/null 2>&1; then
          echo "Kubernetes API is reachable!"
          exit 0
        fi
        sleep 2
      done
      echo "Timed out waiting for Kubernetes API at ${local.cluster_endpoint}" >&2
      exit 1
    EOT
  }

  depends_on = [
    data.talos_cluster_health.this,
    local_sensitive_file.kubeconfig,
  ]
}

