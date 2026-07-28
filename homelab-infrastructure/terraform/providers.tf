provider "proxmox" {
  endpoint = "https://192.168.1.20:8006/api2/json"
  username = "terraform@pve"
  password = var.proxmox_password
  # CA Proxmox установлена на машине, с которой запускается Terraform.
  # Отключать проверку TLS нельзя даже для внутреннего homelab API.
  insecure = false
}
