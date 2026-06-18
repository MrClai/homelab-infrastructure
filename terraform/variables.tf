variable "proxmox_password" {
  description = "Password for terraform@pve user in Proxmox"
  type        = string
  sensitive   = true # не показывать в логах
}

variable "vm_password" {
  description = "Password for VM user"
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Node name for VM"
  type        = string
  default     = "pve"
}

variable "cpu_cores" {
  description = "Number of CPU cores per VM"
  type        = number
  default     = 2
}

variable "cpu_cores_1" {
  description = "Number of CPU cores per VM 1 core"
  type        = number
  default     = 1
}

variable "cpu_sockets" {
  description = "Number of CPU sockets per VM"
  type        = number
  default     = 1
}

variable "cpu_type" {
  description = "CPU type per VM"
  type        = string
  default     = "x86-64-v2-AES"
}

variable "network_bridge" {
  description = "Network bridge per VM"
  type        = string
  default     = "vmbr0"
}

variable "vm_openbao_password" {
  description = "Password for openbao VM user"
  type        = string
  sensitive   = true
}

variable "vm_user_password" {
  description = "Password for VM user"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_public_key_windows" {
  description = "SSH public key for VM access windows"
  type        = string
}
