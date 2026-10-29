terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    system = { source = "neuspaces/system", version = "0.5.0" }
  }
}
variable "proxmox_ssh" {
  type = object({ host = string, user = string, host_key = string })
}
variable "platform_cidr" { type = string }
provider "system" {
  alias = "proxmox"
  ssh {
    host     = var.proxmox_ssh.host
    user     = var.proxmox_ssh.user
    host_key = var.proxmox_ssh.host_key
    agent    = true
  }
  sudo = true
}
module "proxmox" {
  source        = "../../modules/proxmox_host"
  providers     = { system = system.proxmox }
  platform_cidr = var.platform_cidr
}
