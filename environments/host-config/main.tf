terraform {
  required_version = ">= 1.9, < 2.0"
  required_providers {
    system = { source = "neuspaces/system", version = "0.5.0" }
  }
}
variable "proxmox_ssh" {
  type = object({ host = string, user = string })
}
variable "platform_cidr" { type = string }
provider "system" {
  alias = "proxmox"
  ssh {
    host  = var.proxmox_ssh.host
    user  = var.proxmox_ssh.user
    agent = true
  }
  sudo = var.proxmox_ssh.user != "root"
}
module "proxmox" {
  source        = "../../modules/proxmox_host"
  providers     = { system = system.proxmox }
  platform_cidr = var.platform_cidr
}
