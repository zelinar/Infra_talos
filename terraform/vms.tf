# ==============================================================================
# Proxmox Virtual Machines for Talos Nodes
# ==============================================================================

resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each = var.nodes

  name            = each.key
  description     = "Talos Linux ${var.talos_version} (${each.value.role}) - Cluster: ${var.cluster_name}"
  node_name       = coalesce(each.value.target_node, var.proxmox_node)
  vm_id           = each.value.vm_id
  on_boot         = each.value.onboot
  stop_on_destroy = true

  tags = ["talos", "kubernetes", var.cluster_name, each.value.role]

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  operating_system {
    type = "l26"
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = each.value.cpu_type
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = 0 # Disable memory ballooning for Kubernetes stability
  }

  # Boot from scsi0 (installed Talos OS) first, fallback to ide3 (Talos live ISO on first boot)
  boot_order = ["scsi0", "ide3"]

  # Talos Live ISO (used on initial boot to enter Maintenance Mode before install to scsi0)
  cdrom {
    file_id   = local.talos_proxmox_iso_id
    interface = "ide3"
  }

  # Primary OS Disk (/dev/sda)
  disk {
    datastore_id = var.proxmox_vm_datastore
    interface    = "scsi0"
    size         = each.value.os_disk_size_gb
    file_format  = "raw"
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  # Optional Dedicated Data Disk for Longhorn (/dev/sdb)
  dynamic "disk" {
    for_each = each.value.data_disk_size_gb > 0 ? [1] : []
    content {
      datastore_id = var.proxmox_vm_datastore
      interface    = "scsi1"
      size         = each.value.data_disk_size_gb
      file_format  = "raw"
      iothread     = true
      ssd          = true
      discard      = "on"
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Proxmox Cloud-Init (NoCloud) drive injects static IP & DNS so Talos Maintenance Mode is immediately reachable
  initialization {
    datastore_id = var.proxmox_vm_datastore
    interface    = "ide2"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.network_cidr_prefix}"
        gateway = var.network_gateway
      }
    }
  }
}
