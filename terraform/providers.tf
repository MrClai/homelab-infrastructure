provider "proxmox" {
  endpoint = "https://192.168.1.20:8006/api2/json"
  username = "terraform@pve"
  password = var.proxmox_password
  insecure = true # самоподписанный сертификат в Proxmox
}
