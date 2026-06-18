# VM1 — k3s Worker
resource "proxmox_virtual_environment_vm" "vm1" {
  name            = "k3s-worker-01"
  node_name       = var.node_name
  vm_id           = 101
  on_boot         = false
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"
  started         = true

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = "40"
    aio          = "io_uring"
    cache        = "none"
    discard      = "ignore"
    file_format  = "raw"
    iothread     = "true"
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }
}


# VM2 — Gitea
resource "proxmox_virtual_environment_vm" "vm2" {
  name            = "Gitea"
  node_name       = var.node_name
  vm_id           = 102
  on_boot         = false
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"
  started         = true

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "data"
    interface    = "scsi0"
    size         = "20"
    aio          = "io_uring"
    cache        = "none"
    discard      = "ignore"
    file_format  = "qcow2"
    iothread     = "true"
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }
}

# VM3 — Woodpecker
resource "proxmox_virtual_environment_vm" "vm3" {
  name            = "woodpecker"
  node_name       = var.node_name
  vm_id           = 103
  on_boot         = false
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"
  started         = true

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "data"
    interface    = "scsi0"
    size         = "20"
    aio          = "io_uring"
    cache        = "none"
    discard      = "ignore"
    file_format  = "qcow2"
    iothread     = "true"
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }
}

# VM4 — OpenBao
resource "proxmox_virtual_environment_vm" "vm_openbao" {
  name            = "openbao"
  node_name       = var.node_name
  vm_id           = 104
  on_boot         = false
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"
  started         = true

  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = "20"
    aio          = "io_uring"
    cache        = "none"
    discard      = "ignore"
    file_format  = "raw"
    iothread     = "true"
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }

  clone {
    vm_id = 9000
  }

  initialization {
    #host_name = "openbao"

    ip_config {
      ipv4 {
        address = "192.168.1.60/24"
        gateway = "192.168.1.1"
      }
    }
    user_account {
      username = "clai"
      password = var.vm_openbao_password
      keys     = [var.ssh_public_key, var.ssh_public_key_windows]
    }
  }
}
# VM5 - Ansible
resource "proxmox_virtual_environment_vm" "vm_ansible_control" {
  name            = "ansible-control"
  node_name       = var.node_name
  vm_id           = 105
  on_boot         = false
  scsi_hardware   = "virtio-scsi-single"
  keyboard_layout = "en-us"
  started         = true

  cpu {
    cores   = var.cpu_cores_1
    sockets = var.cpu_sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = "20"
    aio          = "io_uring"
    cache        = "none"
    discard      = "ignore"
    file_format  = "raw"
    iothread     = "true"
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = true
  }

  operating_system {
    type = "l26"
  }

  clone {
    vm_id = 9000
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.1.80/24"
        gateway = "192.168.1.1"
      }
    }
    user_account {
      username = "clai"
      password = var.vm_password
      keys     = [var.ssh_public_key, var.ssh_public_key_windows]
    }
  }
}
