# ==============================================================================
# Talos Image Factory Schematic & Proxmox ISO Download
# ==============================================================================

locals {
  nvidia_extensions_map = {
    lts = [
      "siderolabs/nonfree-kmod-nvidia-lts",
      "siderolabs/nvidia-container-toolkit-lts",
    ]
    production = [
      "siderolabs/nonfree-kmod-nvidia-production",
      "siderolabs/nvidia-container-toolkit-production",
    ]
    open-production = [
      "siderolabs/nvidia-open-gpu-kernel-modules-production",
      "siderolabs/nvidia-container-toolkit-production",
    ]
  }

  gpu_talos_extensions = distinct(concat(
    var.talos_system_extensions,
    local.nvidia_extensions_map[var.nvidia_driver_branch]
  ))
}

# 1. Base Schematic (used for the shared Live ISO and all non-GPU nodes)
# Must NOT include nvidia-container-toolkit so ext-nvidia-persistenced does not hang VMs without a GPU
data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = var.talos_system_extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info[*].name
      }
    }
  })
}

# 2. GPU Schematic (used ONLY as installer_image for worker nodes with physical gpu_pci_devices attached)
data "talos_image_factory_extensions_versions" "gpu" {
  talos_version = var.talos_version
  filters = {
    names = local.gpu_talos_extensions
  }
}

resource "talos_image_factory_schematic" "gpu" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = data.talos_image_factory_extensions_versions.gpu.extensions_info[*].name
      }
    }
  })
}

locals {
  talos_factory_iso_url     = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${var.talos_version}/nocloud-amd64.iso"
  talos_installer_image     = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
  talos_gpu_installer_image = "factory.talos.dev/installer/${talos_image_factory_schematic.gpu.id}:${var.talos_version}"
  talos_proxmox_iso_id      = var.download_talos_iso ? proxmox_virtual_environment_download_file.talos_nocloud_iso[0].id : var.existing_talos_iso_file_id
}

resource "proxmox_virtual_environment_download_file" "talos_nocloud_iso" {
  count        = var.download_talos_iso ? 1 : 0
  content_type = "iso"
  datastore_id = var.proxmox_iso_datastore
  node_name    = var.proxmox_node
  url          = local.talos_factory_iso_url
  file_name    = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 12)}-nocloud-amd64.iso"
  overwrite    = true
}
