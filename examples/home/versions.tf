terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    proxmox = { source = "bpg/proxmox" }
    pihole  = { source = "lukaspustina/pihole" }
    restful = { source = "magodo/restful" }
    system  = { source = "neuspaces/system" }
  }
}
