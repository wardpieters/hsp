terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.118.1" }
    pihole  = { source = "lukaspustina/pihole", version = "0.3.1" }
    restful = { source = "magodo/restful", version = "0.25.2" }
  }
}
